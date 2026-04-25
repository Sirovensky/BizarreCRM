/**
 * Supplier Catalog page
 * - Shows stats for Mobilesentrix + PhoneLcdParts catalogs
 * - Start sync jobs
 * - Search/browse catalog items
 * - Import catalog item directly to local inventory
 * - Browse by device model
 */
import { useState, useRef, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  RefreshCw, Search, Download, Package, Loader2, ExternalLink,
  CheckCircle2, AlertCircle, Clock, X, Filter, Upload, Info,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { catalogApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { getIFixitUrl } from '@/utils/ifixit';
// @audit-fixed (WEB-FF-003 / Fixer-UUU 2026-04-25): replace bare `n.toLocaleString()` with shared formatNumber.
import { formatCurrency, formatDate, formatDateTime, formatNumber } from '@/utils/format';

const SOURCES = [
  { key: 'mobilesentrix',  label: 'Mobilesentrix',   url: 'https://www.mobilesentrix.com', color: 'blue'   },
  { key: 'phonelcdparts',  label: 'PhoneLcdParts',   url: 'https://www.phonelcdparts.com', color: 'purple' },
] as const;

function StatusBadge({ status }: { status: string }) {
  const map: Record<string, { cls: string; icon: typeof Clock }> = {
    done:    { cls: 'bg-green-100  text-green-700  dark:bg-green-900/30  dark:text-green-400',  icon: CheckCircle2 },
    running: { cls: 'bg-blue-100   text-blue-700   dark:bg-blue-900/30   dark:text-blue-400',   icon: RefreshCw    },
    pending: { cls: 'bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-300', icon: Clock       },
    failed:  { cls: 'bg-red-100    text-red-700    dark:bg-red-900/30    dark:text-red-400',    icon: AlertCircle  },
  };
  const cfg = map[status] ?? map.pending;
  const Icon = cfg.icon;
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium ${cfg.cls}`}>
      <Icon className={cn('h-3 w-3', status === 'running' && 'animate-spin')} />
      {status}
    </span>
  );
}

// Only accept http/https URLs from the supplier catalog. Without this guard a
// poisoned `product_url` (e.g. `javascript:alert(document.cookie)`) would
// execute in the user's tab when they click the "open product page" icon.
function safeProductUrl(raw: unknown): string | null {
  if (typeof raw !== 'string' || !raw) return null;
  try {
    const parsed = new URL(raw);
    if (parsed.protocol === 'http:' || parsed.protocol === 'https:') return parsed.href;
  } catch { /* fall through */ }
  return null;
}

// SCAN-992b: the catalog-item and job-row renderers reach into many
// optional fields that vary across scraper sources. Use interfaces that
// extend `Record<string, any>` — named fields give compile-time help for
// the common subset, tenant/source-specific extras still access freely
// via the index signature (no cast churn). Matches the pattern the
// PrintPage typing landed on in SCAN-1014.
interface CatalogDeviceModel {
  id: number;
  name: string;
  manufacturer_name?: string;
  ifixit_url?: string | null;
  [key: string]: unknown;
}

interface CatalogJob extends Record<string, any> {
  id?: number;
  source?: string;
  status?: string;
  created_at?: string;
  finished_at?: string | null;
  items_processed?: number;
  items_inserted?: number;
  items_updated?: number;
  error_message?: string | null;
}

interface CatalogItem extends Record<string, any> {
  id?: number;
  source?: string;
  external_id?: string | null;
  sku?: string | null;
  name?: string;
  // price/compare_price/image_url/product_url left to the index signature
  // because consumers (formatCurrency, safeProductUrl, imgSrc) use their
  // own coercion and permissive input accepts multiple shapes.
  category?: string | null;
  in_stock?: number | boolean;
  last_synced?: string | null;
}

export function CatalogPage() {
  const qc = useQueryClient();
  const [activeTab, setActiveTab] = useState<'browse' | 'import'>('browse');
  const [activeSource, setActiveSource] = useState<string>('');
  const [deviceModelId, setDeviceModelId] = useState<number | null>(null);
  const [deviceModelName, setDeviceModelName] = useState('');
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [importModal, setImportModal] = useState<any>(null);
  const [markupPct, setMarkupPct] = useState(30);

  // WEB-FX-003: Esc dismisses the import-to-inventory modal.
  useEffect(() => {
    if (!importModal) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setImportModal(null);
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [importModal]);

  // Debounce search
  const catSearchTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const handleSearchChange = (val: string) => {
    setSearch(val);
    if (catSearchTimerRef.current) clearTimeout(catSearchTimerRef.current);
    catSearchTimerRef.current = setTimeout(() => setDebouncedSearch(val), 350);
  };

  // Queries
  const { data: statsData, isLoading: statsLoading } = useQuery({
    queryKey: ['catalog-stats'],
    queryFn: catalogApi.getStats,
    refetchInterval: 5000, // poll while syncing
    staleTime: 4500, // just under the 5s interval — no redundant refetch on remount
  });
  const stats = (statsData?.data?.data as any) || {};

  const { data: jobsData } = useQuery({
    queryKey: ['catalog-jobs'],
    queryFn: catalogApi.getJobs,
    refetchInterval: 3000,
    staleTime: 2500, // just under the 3s interval
  });
  const jobs: CatalogJob[] = Array.isArray(jobsData?.data?.data) ? (jobsData?.data?.data as CatalogJob[]) : [];

  const { data: catalogData, isLoading: catalogLoading } = useQuery({
    queryKey: ['catalog-search', debouncedSearch, activeSource, deviceModelId],
    queryFn: () => catalogApi.search({
      q: debouncedSearch || undefined,
      source: activeSource || undefined,
      device_model_id: deviceModelId ?? undefined,
      limit: 60,
    }),
  });
  const items: CatalogItem[] = Array.isArray(catalogData?.data?.data?.items)
    ? (catalogData?.data?.data?.items as CatalogItem[])
    : [];
  const total: number = (catalogData?.data?.data?.total as number) || 0;

  // Device model search for filter
  const [modelSearch, setModelSearch] = useState('');
  const [modelResults, setModelResults] = useState<CatalogDeviceModel[]>([]);
  const handleModelSearch = async (q: string) => {
    setModelSearch(q);
    if (q.length < 2) { setModelResults([]); return; }
    try {
      const r = await catalogApi.searchDevices({ q, limit: 8 });
      const raw = r.data?.data;
      setModelResults(Array.isArray(raw) ? (raw as CatalogDeviceModel[]) : []);
    } catch (err) {
      // Surface failures instead of silently returning empty results; users
      // otherwise think "no matches" when the backend is actually 401/down.
      console.error('[catalog] device-model search failed', err);
      setModelResults([]);
    }
  };

  // Sync mutation
  const syncMutation = useMutation({
    mutationFn: (source: 'mobilesentrix' | 'phonelcdparts') => catalogApi.startSync(source),
    onSuccess: (_res, source) => {
      toast.success(`Sync started for ${source}`);
      qc.invalidateQueries({ queryKey: ['catalog-stats'] });
      qc.invalidateQueries({ queryKey: ['catalog-jobs'] });
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to start sync'),
  });

  // CSV import state
  const [csvSource, setCsvSource] = useState('mobilesentrix');
  const [csvText, setCsvText] = useState('');
  const [csvImporting, setCsvImporting] = useState(false);
  const csvInputRef = useRef<HTMLInputElement>(null);

  const handleCsvFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    if (!f) return;
    const reader = new FileReader();
    reader.onload = (ev) => setCsvText((ev.target?.result as string) || '');
    reader.readAsText(f);
  };

  // @audit-fixed WEB-FB-004: RFC-4180-ish tokenizer that handles quoted fields
  // containing commas, embedded quotes (escaped as ""), CRLF/LF/CR row separators,
  // and quoted newlines. Replaces the previous naive split(',') / split('\n').
  const parseCsvRows = (csv: string): string[][] => {
    const rows: string[][] = [];
    let row: string[] = [];
    let field = '';
    let inQuotes = false;
    for (let i = 0; i < csv.length; i++) {
      const ch = csv[i];
      if (inQuotes) {
        if (ch === '"') {
          if (csv[i + 1] === '"') {
            // Escaped quote inside a quoted field.
            field += '"';
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field += ch;
        }
        continue;
      }
      if (ch === '"') {
        inQuotes = true;
        continue;
      }
      if (ch === ',') {
        row.push(field);
        field = '';
        continue;
      }
      if (ch === '\r') {
        // Treat CR / CRLF as row terminator.
        row.push(field);
        rows.push(row);
        row = [];
        field = '';
        if (csv[i + 1] === '\n') i++;
        continue;
      }
      if (ch === '\n') {
        row.push(field);
        rows.push(row);
        row = [];
        field = '';
        continue;
      }
      field += ch;
    }
    // Flush the trailing field/row if the file didn't end with a newline.
    if (field.length > 0 || row.length > 0) {
      row.push(field);
      rows.push(row);
    }
    // Drop fully-blank rows (e.g. trailing newline produces one).
    return rows.filter((r) => r.some((c) => c.trim() !== ''));
  };

  const parseCsvToItems = (csv: string) => {
    const rows = parseCsvRows(csv);
    if (rows.length < 2) return [];
    const headers = rows[0].map((h) => h.trim().toLowerCase());
    return rows.slice(1).map((vals) => {
      const obj: Record<string, string> = {};
      headers.forEach((h, i) => { obj[h] = (vals[i] ?? '').trim(); });
      return {
        sku: obj.sku || obj['part number'] || obj['part_number'] || '',
        name: obj.name || obj.title || obj['product name'] || obj['product_name'] || '',
        price: parseFloat(obj.price || obj['your price'] || obj['cost'] || '0') || 0,
        category: obj.category || obj['product type'] || obj['product_type'] || '',
        image_url: obj.image || obj['image url'] || obj['image_url'] || '',
        compatible_devices: (obj.compatible || obj.compatibility || obj['compatible devices'] || '').split(/[;|]/).map((s: string) => s.trim()).filter(Boolean),
      };
    }).filter((item) => item.name && item.price > 0);
  };

  const handleCsvImport = async () => {
    if (!csvText.trim()) { toast.error('Paste CSV text or choose a file'); return; }
    const items = parseCsvToItems(csvText);
    if (items.length === 0) { toast.error('No valid items found in CSV. Check column headers: sku, name, price, category, compatible_devices'); return; }
    setCsvImporting(true);
    try {
      const res = await catalogApi.bulkImport({ source: csvSource, items });
      const data = res.data as any;
      if (data.success) {
        toast.success(`Imported ${data.data.upserted} items from CSV`);
        setCsvText('');
        qc.invalidateQueries({ queryKey: ['catalog-search'] });
        qc.invalidateQueries({ queryKey: ['catalog-stats'] });
        setActiveTab('browse');
      } else {
        toast.error(data.message || 'Import failed');
      }
    } catch (e: any) {
      toast.error(e?.response?.data?.message || e.message || 'Import failed');
    }
    setCsvImporting(false);
  };

  // Import mutation
  const importMutation = useMutation({
    mutationFn: ({ id, markup }: { id: number; markup: number }) =>
      catalogApi.importItem(id, { markup_pct: markup }),
    onSuccess: () => {
      toast.success('Item added to inventory');
      setImportModal(null);
      qc.invalidateQueries({ queryKey: ['inventory'] });
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to import'),
  });

  const runningJobs = jobs.filter((j) => j.status === 'running');

  return (
    <div>
      {/* Header */}
      <div className="mb-6 flex flex-wrap items-center gap-4">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Supplier Catalog</h1>
          <p className="text-sm text-surface-500 mt-0.5">Browse and import parts from Mobilesentrix &amp; PhoneLcdParts</p>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 mb-6 border-b border-surface-200 dark:border-surface-700">
        {(['browse', 'import'] as const).map((tab) => (
          <button key={tab} onClick={() => setActiveTab(tab)}
            className={cn('px-4 py-2 text-sm font-medium capitalize border-b-2 -mb-px transition-colors',
              activeTab === tab
                ? 'border-primary-500 text-primary-700 dark:text-primary-300'
                : 'border-transparent text-surface-500 hover:text-surface-700 dark:hover:text-surface-300'
            )}>
            {tab === 'browse' ? 'Browse Catalog' : 'Import from CSV'}
          </button>
        ))}
      </div>

      {/* CSV Import tab */}
      {activeTab === 'import' && (
        <div className="max-w-2xl">
          <div className="card p-5 mb-4 bg-blue-50 dark:bg-blue-900/20 border-blue-200 dark:border-blue-800">
            <div className="flex gap-3">
              <Info className="h-5 w-5 text-blue-600 flex-shrink-0 mt-0.5" />
              <div className="text-sm text-blue-800 dark:text-blue-200 space-y-1">
                <p className="font-semibold">How to import your supplier catalog:</p>
                <ol className="list-decimal list-inside space-y-1 text-blue-700 dark:text-blue-300">
                  <li>Log into your <a href="https://www.mobilesentrix.com" target="_blank" rel="noopener noreferrer" className="underline">Mobilesentrix</a> or <a href="https://www.phonelcdparts.com" target="_blank" rel="noopener noreferrer" className="underline">PhoneLcdParts</a> account</li>
                  <li>Download your product/parts catalog as CSV or Excel</li>
                  <li>Upload it here — we'll match parts to device models automatically</li>
                </ol>
                <p className="mt-2 text-xs">Expected CSV columns: <code className="bg-blue-100 dark:bg-blue-900 px-1 rounded">sku, name, price, category, compatible_devices</code> (semicolon-separated)</p>
              </div>
            </div>
          </div>

          <div className="card p-5 space-y-4">
            <div>
              <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Source</label>
              <select value={csvSource} onChange={(e) => setCsvSource(e.target.value)} className="input w-full">
                <option value="mobilesentrix">Mobilesentrix</option>
                <option value="phonelcdparts">PhoneLcdParts</option>
                <option value="other">Other Supplier</option>
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Upload CSV file</label>
              <input ref={csvInputRef} type="file" accept=".csv,.txt" onChange={handleCsvFile} className="hidden" />
              <button onClick={() => csvInputRef.current?.click()}
                className="inline-flex items-center gap-2 px-4 py-2.5 text-sm font-medium rounded-xl border-2 border-dashed border-surface-300 dark:border-surface-600 text-surface-500 hover:border-primary-400 hover:text-primary-600 transition-colors w-full justify-center">
                <Upload className="h-4 w-4" /> Choose CSV file
              </button>
            </div>

            <div>
              <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Or paste CSV text</label>
              <textarea
                value={csvText}
                onChange={(e) => setCsvText(e.target.value)}
                className="input w-full font-mono text-xs"
                rows={10}
                placeholder={`sku,name,price,category,compatible_devices\nABC123,OLED Assembly for iPhone 14,45.99,Screen,iPhone 14;iPhone 14 Plus\nDEF456,Battery for Samsung Galaxy S23,12.50,Battery,Samsung Galaxy S23`}
              />
              {csvText && (
                <p className="text-xs text-surface-400 mt-1">
                  {parseCsvToItems(csvText).length} valid items detected
                </p>
              )}
            </div>

            <button
              onClick={handleCsvImport}
              disabled={csvImporting || !csvText.trim()}
              className="btn-primary w-full">
              {csvImporting
                ? <><Loader2 className="h-4 w-4 animate-spin" /> Importing…</>
                : <><Upload className="h-4 w-4" /> Import to Catalog</>}
            </button>
          </div>
        </div>
      )}

      {/* Browse tab content starts here */}
      {activeTab === 'browse' && <>

      {/* Source cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-6">
        {SOURCES.map((src) => {
          const count = stats[`${src.key}_count`] ?? 0;
          const lastSync = stats[`${src.key}_last_sync`];
          const running = runningJobs.some((j) => j.source === src.key);
          return (
            <div key={src.key} className="card p-4 flex items-center gap-4">
              <div className={cn('h-12 w-12 rounded-xl flex items-center justify-center flex-shrink-0',
                src.color === 'blue' ? 'bg-blue-100 dark:bg-blue-900/30' : 'bg-purple-100 dark:bg-purple-900/30'
              )}>
                <Package className={cn('h-6 w-6', src.color === 'blue' ? 'text-blue-600 dark:text-blue-400' : 'text-purple-600 dark:text-purple-400')} />
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-semibold text-surface-800 dark:text-surface-200">{src.label}</p>
                <p className="text-sm text-surface-500">
                  {/* @audit-fixed: use formatDate helper instead of browser locale */}
                  {formatNumber(count)} items cataloged
                  {lastSync && <span className="ml-2 text-xs">· last sync {formatDate(lastSync)}</span>}
                </p>
                {count === 0 && <p className="text-xs text-surface-400 mt-0.5">Catalog syncs automatically daily</p>}
              </div>
              <div className="flex items-center gap-2">
                <a href={src.url} target="_blank" rel="noopener noreferrer"
                  className="p-1.5 text-surface-400 hover:text-surface-600 transition-colors" title="Visit supplier website">
                  <ExternalLink className="h-4 w-4" />
                </a>
                {running && (
                  <span className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg bg-blue-50 text-blue-600 dark:bg-blue-900/20">
                    <RefreshCw className="h-3.5 w-3.5 animate-spin" /> Syncing...
                  </span>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* Running job progress */}
      {runningJobs.length > 0 && (
        <div className="mb-4 rounded-xl bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 p-3 flex items-center gap-3">
          <Loader2 className="h-4 w-4 animate-spin text-blue-600" />
          <div className="flex-1">
            {runningJobs.map((j) => (
              <p key={j.id} className="text-sm text-blue-800 dark:text-blue-200">
                Syncing {j.source}: {j.items_upserted ?? 0} items fetched (page {j.pages_done ?? 0})…
              </p>
            ))}
          </div>
        </div>
      )}

      {/* Filters */}
      <div className="card p-4 mb-4">
        <div className="flex flex-wrap gap-3 items-start">
          {/* Text search */}
          <div className="relative flex-1 min-w-[200px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
            <input
              value={search}
              onChange={(e) => handleSearchChange(e.target.value)}
              className="input w-full pl-9"
              placeholder='Search catalog — e.g. "iPhone 14 OLED", "Galaxy S23 battery"…'
            />
            {search && (
              <button onClick={() => { setSearch(''); setDebouncedSearch(''); }} className="absolute right-3 top-1/2 -translate-y-1/2 text-surface-400 hover:text-surface-600">
                <X className="h-4 w-4" />
              </button>
            )}
          </div>

          {/* Source filter */}
          <div className="flex gap-1">
            {(['', 'mobilesentrix', 'phonelcdparts'] as const).map((s) => (
              <button key={s || 'all'}
                onClick={() => setActiveSource(s)}
                className={cn('px-3 py-2 text-sm rounded-lg border transition-colors',
                  activeSource === s
                    ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/20 text-primary-700 dark:text-primary-300'
                    : 'border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:border-surface-300'
                )}>
                {s === '' ? 'All sources' : s === 'mobilesentrix' ? 'Mobilesentrix' : 'PhoneLcdParts'}
              </button>
            ))}
          </div>

          {/* Device model filter */}
          <div className="relative min-w-[220px]">
            {deviceModelId ? (
              <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-primary-50 dark:bg-primary-900/20 border border-primary-200 dark:border-primary-700 text-sm">
                <Filter className="h-3.5 w-3.5 text-primary-500" />
                <span className="flex-1 text-primary-800 dark:text-primary-200 truncate">{deviceModelName}</span>
                <button onClick={() => { setDeviceModelId(null); setDeviceModelName(''); setModelSearch(''); setModelResults([]); }}>
                  <X className="h-3.5 w-3.5 text-primary-400" />
                </button>
              </div>
            ) : (
              <>
                <Filter className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
                <input
                  value={modelSearch}
                  onChange={(e) => handleModelSearch(e.target.value)}
                  className="input w-full pl-9"
                  placeholder="Filter by device model…"
                />
              </>
            )}
            {modelResults.length > 0 && !deviceModelId && (
              <div className="absolute z-20 top-full mt-1 left-0 right-0 rounded-xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 shadow-lg max-h-52 overflow-y-auto">
                {modelResults.map((m) => (
                  <div key={m.id} className="flex items-center gap-1 hover:bg-surface-50 dark:hover:bg-surface-700">
                    <button
                      onClick={() => { setDeviceModelId(m.id); setDeviceModelName(`${m.manufacturer_name} ${m.name}`); setModelSearch(''); setModelResults([]); }}
                      className="flex-1 flex items-center gap-2 px-3 py-2.5 text-left text-sm">
                      <span className="flex-1 font-medium text-surface-800 dark:text-surface-200">{m.name}</span>
                      <span className="text-xs text-surface-400">{m.manufacturer_name}</span>
                    </button>
                    <a href={getIFixitUrl(`${m.manufacturer_name} ${m.name}`, m.ifixit_url)} target="_blank" rel="noopener noreferrer"
                      onClick={(e) => e.stopPropagation()}
                      className="px-2 py-1 text-[10px] text-blue-500 hover:text-blue-600 hover:underline flex-shrink-0"
                      title="iFixit Repair Guide">
                      iFixit
                    </a>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Results count */}
      <div className="mb-3 flex items-center justify-between">
        <p className="text-sm text-surface-500">
          {catalogLoading ? 'Loading…' : `${formatNumber(total)} items${debouncedSearch ? ` matching "${debouncedSearch}"` : ''}${deviceModelId ? ` for ${deviceModelName}` : ''}`}
        </p>
        {total === 0 && !catalogLoading && stats.total_catalog === 0 && (
          <p className="text-sm text-amber-600 dark:text-amber-400">Sync a catalog above to populate items</p>
        )}
      </div>

      {/* Catalog items grid */}
      {catalogLoading ? (
        <div className="flex items-center justify-center py-16">
          <Loader2 className="h-8 w-8 animate-spin text-primary-500" />
        </div>
      ) : items.length === 0 ? (
        <div className="text-center py-16 text-surface-400">
          <Package className="h-12 w-12 mx-auto mb-3 opacity-30" />
          <p className="font-medium">No items found</p>
          {stats.total_catalog === 0 && (
            <p className="text-sm mt-1">Start by syncing Mobilesentrix or PhoneLcdParts above</p>
          )}
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
          {items.map((item) => {
            const compatDevices: string[] = (() => {
              try { return JSON.parse(item.compatible_devices || '[]'); } catch { return []; }
            })();
            return (
              <div key={item.id} className="card p-3 flex flex-col gap-2 hover:shadow-md transition-shadow">
                {/* Image */}
                <div className="h-28 rounded-lg bg-surface-50 dark:bg-surface-700 flex items-center justify-center overflow-hidden">
                  {item.image_url ? (
                    <img src={item.image_url} alt={item.name} loading="lazy" decoding="async" className="h-full w-full object-contain p-1" />
                  ) : (
                    <Package className="h-10 w-10 text-surface-300" />
                  )}
                </div>

                {/* Name + source */}
                <div className="flex-1">
                  <p className="text-xs text-surface-400 mb-0.5 capitalize">{item.source}</p>
                  <p className="text-sm font-medium text-surface-800 dark:text-surface-200 line-clamp-2 leading-snug">{item.name}</p>
                  {item.sku && (
                    <p className="text-[10px] font-mono text-surface-400 mt-0.5 truncate" title={item.sku}>SKU: {item.sku}</p>
                  )}
                  {compatDevices.length > 0 && (
                    <div className="flex items-center gap-1.5 mt-1">
                      <p className="text-xs text-surface-400 line-clamp-1 flex-1" title={compatDevices.join(', ')}>
                        {compatDevices[0]}{compatDevices.length > 1 ? ` +${compatDevices.length - 1}` : ''}
                      </p>
                      <a href={getIFixitUrl(compatDevices[0])} target="_blank" rel="noopener noreferrer"
                        className="inline-flex items-center gap-0.5 text-[10px] text-blue-500 hover:text-blue-600 hover:underline flex-shrink-0"
                        title="iFixit Repair Guide">
                        <ExternalLink className="h-2.5 w-2.5" /> iFixit
                      </a>
                    </div>
                  )}
                </div>

                {/* Price + actions */}
                {/* @audit-fixed: use formatCurrency for prices */}
                <div className="flex items-center justify-between mt-1">
                  <div>
                    <span className="text-base font-bold text-surface-900 dark:text-surface-100">{item.price ? formatCurrency(item.price) : <span className="text-sm font-medium text-surface-400 italic">Price N/A</span>}</span>
                    {item.compare_price && item.compare_price > item.price && (
                      <span className="text-xs text-surface-400 line-through ml-1">{formatCurrency(item.compare_price)}</span>
                    )}
                  </div>
                  <div className="flex items-center gap-1">
                    {(() => {
                      const url = safeProductUrl(item.product_url);
                      if (!url) return null;
                      return (
                        <a href={url} target="_blank" rel="noopener noreferrer"
                          aria-label={`Open supplier product page for ${item.name}`}
                          className="p-1.5 text-surface-400 hover:text-surface-600 transition-colors">
                          <ExternalLink aria-hidden="true" className="h-3.5 w-3.5" />
                        </a>
                      );
                    })()}
                    <button
                      onClick={() => { setImportModal(item); setMarkupPct(30); }}
                      className="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium bg-primary-600 hover:bg-primary-700 text-white rounded-lg transition-colors">
                      <Download className="h-3 w-3" /> Import
                    </button>
                  </div>
                </div>

                {!item.in_stock && (
                  <p className="text-xs text-red-500 -mt-1">Out of stock at supplier</p>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Recent jobs log */}
      {jobs.length > 0 && (
        <div className="mt-8">
          <h2 className="text-sm font-semibold text-surface-600 dark:text-surface-400 mb-2">Recent sync jobs</h2>
          <div className="card divide-y divide-surface-100 dark:divide-surface-700">
            {jobs.slice(0, 5).map((j) => (
              <div key={j.id} className="flex items-center gap-3 px-4 py-2.5 text-sm">
                <StatusBadge status={j.status ?? 'pending'} />
                <span className="font-medium text-surface-700 dark:text-surface-300 capitalize">{j.source}</span>
                <span className="text-surface-400">{j.items_upserted ?? 0} items · {j.pages_done ?? 0} pages</span>
                {j.error && <span className="text-red-500 truncate">{j.error}</span>}
                <span className="ml-auto text-xs text-surface-400">
                  {/* @audit-fixed: use formatDateTime helper */}
                  {j.finished_at ? formatDateTime(j.finished_at) : j.started_at ? 'Running…' : 'Queued'}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      </> /* end browse tab */}

      {/* Import modal */}
      {importModal && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50"
          onClick={(e) => {
            if (e.target === e.currentTarget) setImportModal(null);
          }}
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="catalog-import-title"
            className="bg-white dark:bg-surface-800 rounded-2xl shadow-xl w-full max-w-md p-6"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between mb-4">
              <h2 id="catalog-import-title" className="text-lg font-bold text-surface-900 dark:text-surface-100">Import to Inventory</h2>
              <button onClick={() => setImportModal(null)} className="text-surface-400 hover:text-surface-600">
                <X className="h-5 w-5" />
              </button>
            </div>

            {importModal.image_url && (
              <img src={importModal.image_url} alt={importModal.name} loading="lazy" decoding="async" className="h-24 w-full object-contain rounded-lg bg-surface-50 dark:bg-surface-700 mb-3" />
            )}

            <p className="text-sm font-medium text-surface-800 dark:text-surface-200 mb-1">{importModal.name}</p>
            {/* @audit-fixed: use formatCurrency */}
            <p className="text-xs text-surface-400 mb-4">Supplier cost: {formatCurrency(importModal.price)}</p>

            <div className="space-y-3">
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
                  Markup % <span className="text-surface-400 font-normal">(applied to cost → retail price)</span>
                </label>
                <div className="flex items-center gap-2">
                  <input
                    type="number"
                    value={markupPct}
                    onChange={(e) => setMarkupPct(Number(e.target.value))}
                    className="input w-24"
                    min={0}
                    max={500}
                  />
                  <span className="text-sm text-surface-500">
                    {/* @audit-fixed: use formatCurrency */}
                    → Retail: <strong className="text-surface-800 dark:text-surface-200">
                      {formatCurrency(importModal.price * (1 + markupPct / 100))}
                    </strong>
                  </span>
                </div>
              </div>
            </div>

            <div className="flex justify-end gap-3 mt-6">
              <button onClick={() => setImportModal(null)} className="btn-outline">Cancel</button>
              <button
                onClick={() => importMutation.mutate({ id: importModal.id, markup: markupPct })}
                disabled={importMutation.isPending}
                className="btn-primary">
                {importMutation.isPending ? <><Loader2 className="h-4 w-4 animate-spin" /> Importing…</> : <><Download className="h-4 w-4" /> Add to Inventory</>}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
