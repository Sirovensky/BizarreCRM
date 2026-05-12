/**
 * Stocktake page — physical count workflow.
 *
 * Top: list of open/recent sessions, "New session" button.
 * Bottom (when session selected): scanner input, running count list with
 *   variance badges, commit / cancel buttons.
 *
 * Cross-ref: criticalaudit.md §48 idea #1.
 */
import { useState, useRef, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import {
  ClipboardList,
  Plus,
  ChevronLeft,
  Check,
  X,
  Loader2,
  ScanBarcode,
  Download,
} from 'lucide-react';
import { api } from '@/api/client';
import { inventoryApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatDateTime, formatCurrency } from '@/utils/format';
// WEB-FB-007 (Fixer-KKK 2026-04-25): swapped native window.confirm for the
// themed async modal — matches the pattern already used on Estimates / POS /
// Customers / Tickets / Invoices, picks up dark mode + brand fonts, and is
// not blocked by Safari's third-party-iframe modal suppression.
import { useConfirmStore } from '@/stores/confirmStore';
import { useAuthStore } from '@/stores/authStore';

interface StocktakeSession {
  id: number;
  name: string;
  location: string | null;
  status: 'open' | 'committed' | 'cancelled';
  opened_at: string;
  committed_at: string | null;
  notes: string | null;
  // WEB-UIUX-1362: hydrated by GET /stocktake list so the card shows
  // progress without drilling into each session. Absent on legacy or
  // GET /stocktake/:id detail responses.
  items_counted?: number;
  items_with_variance?: number;
}

interface StocktakeCount {
  id: number;
  inventory_item_id: number;
  expected_qty: number;
  counted_qty: number;
  variance: number;
  notes: string | null;
  counted_at: string;
  name?: string;
  sku?: string;
  cost_price?: number;
  // WEB-UIUX-1356: server already returns `i.in_stock as current_in_stock`
  // in GET /stocktake/:id (stocktake.routes.ts:179) — the live in_stock at
  // query time. Used here to flag rows whose expected_qty baseline has
  // drifted because of concurrent sales since the row was scanned.
  current_in_stock?: number;
}

interface StocktakeDetail {
  session: StocktakeSession;
  counts: StocktakeCount[];
  summary: {
    items_counted: number;
    items_with_variance: number;
    total_variance: number;
    surplus: number;
    shortage: number;
  };
}

export function StocktakePage() {
  const queryClient = useQueryClient();
  const user = useAuthStore((s) => s.user);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [showNew, setShowNew] = useState(false);
  const [newName, setNewName] = useState('');
  const [newLocation, setNewLocation] = useState('');
  // WEB-UIUX-1358: session-level notes field state
  const [newNotes, setNewNotes] = useState('');
  const [scanInput, setScanInput] = useState('');
  const [manualCountedQty, setManualCountedQty] = useState('');
  // WEB-UIUX-1357: per-count notes — large variance ("surplus +50") needs
  // a reason for the auditor; server already persists notes on the row.
  const [scanNote, setScanNote] = useState('');
  // WEB-UIUX-1365: search + variance-filter for the counts table.
  const [countsSearch, setCountsSearch] = useState('');
  const [varianceFilter, setVarianceFilter] = useState<'all' | 'variance' | 'shortage' | 'surplus' | 'match'>('all');
  // WEB-UIUX-1367: session list filters — server already accepts ?status=.
  const [sessionStatusFilter, setSessionStatusFilter] = useState<'' | 'open' | 'committed' | 'cancelled'>('');
  const [sessionSearch, setSessionSearch] = useState('');
  const scanRef = useRef<HTMLInputElement>(null);

  // WEB-UIUX-1373: capture isPending to drive loading skeleton
  const { data: sessionsData, isPending: sessionsIsPending } = useQuery({
    queryKey: ['stocktakes', sessionStatusFilter],
    queryFn: async () => {
      const params: Record<string, string> = {};
      if (sessionStatusFilter) params.status = sessionStatusFilter;
      const res = await api.get<{ success: boolean; data: StocktakeSession[] }>('/stocktake', { params });
      return res.data.data;
    },
  });
  const sessions: StocktakeSession[] = (sessionsData || []).filter((s) => {
    if (sessionSearch.trim()) {
      const q = sessionSearch.trim().toLowerCase();
      return String(s.name ?? '').toLowerCase().includes(q)
        || String(s.location ?? '').toLowerCase().includes(q);
    }
    return true;
  });

  const { data: detailData } = useQuery({
    queryKey: ['stocktake', selectedId],
    queryFn: async () => {
      if (!selectedId) return null;
      const res = await api.get<{ success: boolean; data: StocktakeDetail }>(
        `/stocktake/${selectedId}`,
      );
      return res.data.data;
    },
    enabled: !!selectedId,
  });

  // WEB-UIUX-1365: filtered + searched counts list. Recomputed on every
  // render; cheap enough at 1k rows.
  const filteredCounts = (detailData?.counts ?? []).filter((c) => {
    if (countsSearch.trim()) {
      const q = countsSearch.trim().toLowerCase();
      if (!String(c.name ?? '').toLowerCase().includes(q) && !String(c.sku ?? '').toLowerCase().includes(q)) {
        return false;
      }
    }
    if (varianceFilter === 'variance' && c.variance === 0) return false;
    if (varianceFilter === 'shortage' && c.variance >= 0) return false;
    if (varianceFilter === 'surplus' && c.variance <= 0) return false;
    if (varianceFilter === 'match' && c.variance !== 0) return false;
    return true;
  });

  useEffect(() => {
    if (detailData?.session.status === 'open') {
      scanRef.current?.focus();
    }
  }, [detailData?.session.status, detailData?.counts.length]);

  const createMut = useMutation({
    // WEB-UIUX-1358: include optional notes in session creation payload
    mutationFn: async (body: { name: string; location: string; notes?: string }) => {
      const res = await api.post<{ success: boolean; data: StocktakeSession }>(
        '/stocktake',
        body,
      );
      return res.data.data;
    },
    onSuccess: (session) => {
      toast.success(`Stocktake "${session.name}" opened`);
      queryClient.invalidateQueries({ queryKey: ['stocktakes'] });
      setShowNew(false);
      setNewName('');
      setNewLocation('');
      setNewNotes(''); // WEB-UIUX-1358: reset notes field
      setSelectedId(session.id);
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to open session'),
  });

  const scanMut = useMutation({
    mutationFn: async (body: { inventory_item_id: number; counted_qty: number; notes?: string }) => {
      const res = await api.post(`/stocktake/${selectedId}/counts`, body);
      return res.data.data;
    },
    // WEB-UIUX-1360: echo item name + variance on successful scan
    onSuccess: (data: any) => {
      queryClient.invalidateQueries({ queryKey: ['stocktake', selectedId] });
      const itemName = data?.name ?? `Item #${data?.inventory_item_id ?? '?'}`;
      const counted = data?.counted_qty ?? 0;
      const variance = data?.variance ?? 0;
      const varianceStr = variance > 0 ? `+${variance}` : `${variance}`;
      const msg = `${itemName} → counted ${counted} (variance: ${varianceStr})`;
      if (variance !== 0) {
        toast(msg, {
          icon: variance > 0 ? '📈' : '📉',
          style: { borderLeft: `4px solid ${variance > 0 ? '#16a34a' : '#dc2626'}` },
        });
      } else {
        toast.success(msg);
      }
      setScanInput('');
      setManualCountedQty('');
      scanRef.current?.focus();
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Scan failed'),
  });

  // WEB-UIUX-1354: per-row delete so a typo'd scan can be removed without
  // an inverse re-scan. Server gates on session.status='open'.
  const deleteCountMut = useMutation({
    mutationFn: async (inventoryItemId: number) => {
      const res = await api.delete(`/stocktake/${selectedId}/counts/${inventoryItemId}`);
      return res.data;
    },
    onSuccess: () => {
      toast.success('Row removed');
      queryClient.invalidateQueries({ queryKey: ['stocktake', selectedId] });
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Could not remove row'),
  });

  const commitMut = useMutation({
    mutationFn: async () => {
      const res = await api.post(`/stocktake/${selectedId}/commit`);
      return res.data.data;
    },
    onSuccess: (data: any) => {
      toast.success(`Committed: ${data.items_adjusted} items adjusted`);
      queryClient.invalidateQueries({ queryKey: ['stocktakes'] });
      queryClient.invalidateQueries({ queryKey: ['stocktake', selectedId] });
      queryClient.invalidateQueries({ queryKey: ['pos-products'] });
      // WEB-UIUX-889: inventory list/detail/abc/low-stock caches all hold
      // pre-commit `in_stock` — invalidate so they reflect the adjusted counts.
      queryClient.invalidateQueries({ queryKey: ['inventory'] });
      queryClient.invalidateQueries({ queryKey: ['inventory-detail'] });
      queryClient.invalidateQueries({ queryKey: ['abc-analysis'] });
      queryClient.invalidateQueries({ queryKey: ['low-stock'] });
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Commit failed'),
  });

  const cancelMut = useMutation({
    mutationFn: async () => {
      const res = await api.post(`/stocktake/${selectedId}/cancel`);
      return res.data.data;
    },
    onSuccess: () => {
      toast.success('Stocktake cancelled');
      queryClient.invalidateQueries({ queryKey: ['stocktakes'] });
      queryClient.invalidateQueries({ queryKey: ['stocktake', selectedId] });
    },
  });

  const handleScan = async (e: React.FormEvent) => {
    e.preventDefault();
    const q = scanInput.trim();
    if (!q) return;
    // WEB-UIUX-793: digits-only 8+ char input is a barcode — use the exact
    // lookupBarcode endpoint so a LIKE-match on a longer product name never
    // silently wins over the true UPC hit.
    const isBarcode = /^\d{8,}$/.test(q);
    try {
      let item: { id: number; name: string } | undefined;
      if (isBarcode) {
        const res = await inventoryApi.lookupBarcode(q);
        item = res.data?.data ?? undefined;
      } else {
        // WEB-UIUX-1353: try exact-SKU lookup first so a scan that prefixes
        // another item doesn't silently credit the prefix. 404 → fall back
        // to fuzzy keyword (existing behaviour). 409 (duplicate active SKU)
        // surfaces a structured toast asking the operator to resolve the
        // dup rather than crediting an arbitrary row.
        try {
          const exact = await api.get('/inventory/by-sku', { params: { sku: q } });
          item = exact.data?.data ?? undefined;
        } catch (err: any) {
          const status = err?.response?.status;
          if (status === 409) {
            toast.error(err?.response?.data?.message || `Duplicate active SKU '${q}' — resolve in Inventory first.`);
            return;
          }
          if (status !== 404) {
            throw err;
          }
          // 404 → not an exact SKU; fall through to fuzzy.
          const res = await api.get('/inventory', { params: { keyword: q, pagesize: 1 } });
          const items = res.data.data?.items || [];
          item = items[0];
        }
      }
      if (!item) {
        // WEB-UIUX-1381: append fuzzy-match hint when exact lookup returns zero
        let hint = '';
        if (!isBarcode) {
          try {
            const fuzzyRes = await api.get('/inventory', { params: { keyword: q, pagesize: 3 } });
            const fuzzyItems: { name: string }[] = fuzzyRes.data.data?.items || [];
            if (fuzzyItems.length > 0) {
              const names = fuzzyItems.map((fi) => fi.name).join(', ');
              hint = ` — did you mean: ${names}?`;
            } else {
              hint = ' (Try a partial SKU)';
            }
          } catch {
            hint = ' (Try a partial SKU)';
          }
        } else {
          hint = ' (Try a partial SKU)';
        }
        toast.error(`No item matching "${q}"${hint}`);
        return;
      }
      const existingCount = detailData?.counts.find((c) => c.inventory_item_id === item.id);
      // Validate manual count before firing the mutation. Server rejects
      // NaN / negatives, but the toast it returns is generic; pre-validating
      // keeps the cashier in the field with their typo highlighted.
      let counted: number;
      if (manualCountedQty) {
        const parsed = parseInt(manualCountedQty, 10);
        if (!Number.isInteger(parsed) || parsed < 0) {
          toast.error('Enter a non-negative whole number for the count');
          return;
        }
        counted = parsed;
      } else {
        // quick-scan: increment physical count by 1
        counted = existingCount ? existingCount.counted_qty + 1 : 1;
      }
      // WEB-UIUX-1357: include note + reset on submit so each count carries
      // its own context to the stock_movements audit row.
      scanMut.mutate({
        inventory_item_id: item.id,
        counted_qty: counted,
        notes: scanNote.trim() || undefined,
      });
      setScanNote('');
    } catch (err: any) {
      toast.error(err?.response?.data?.message || 'Lookup failed');
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          {/* WEB-UIUX-1380: preserve the user's tab/filter state on
              Inventory by going back through history when the previous
              route was /inventory; fall back to a fresh /inventory link
              when this is a direct landing. */}
          <button
            type="button"
            onClick={() => {
              if (typeof document !== 'undefined' && document.referrer && document.referrer.includes('/inventory')) {
                window.history.back();
              } else {
                window.location.href = '/inventory';
              }
            }}
            className="text-sm text-primary-600 hover:underline inline-flex items-center gap-1"
          >
            <ChevronLeft className="h-4 w-4" /> Back to Inventory
          </button>
          <h1 className="text-2xl font-bold mt-2 flex items-center gap-2">
            <ClipboardList className="h-6 w-6" /> Stocktakes
          </h1>
          <p className="text-sm text-surface-500">Physical count sessions with variance tracking</p>
        </div>
        <button
          onClick={() => setShowNew(true)}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-primary-950 hover:bg-primary-700"
        >
          <Plus className="h-4 w-4" /> New Stocktake
        </button>
      </div>

      {showNew && (
        <div className="rounded-lg border border-surface-200 bg-white p-4 dark:bg-surface-800 dark:border-surface-700">
          <h2 className="font-semibold mb-3">Open a new stocktake session</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <input
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              placeholder="Session name (e.g. Q2 2026 full count)"
              className="rounded-md border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 dark:placeholder:text-surface-500"
            />
            <input
              value={newLocation}
              onChange={(e) => setNewLocation(e.target.value)}
              placeholder="Location (optional)"
              className="rounded-md border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 dark:placeholder:text-surface-500"
            />
          </div>
          {/* WEB-UIUX-1358: optional session-level notes accepted by POST /stocktake */}
          <div className="mt-3">
            <textarea
              value={newNotes}
              onChange={(e) => setNewNotes(e.target.value)}
              placeholder="Notes (optional)"
              rows={2}
              className="w-full rounded-md border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 dark:placeholder:text-surface-500 resize-none"
            />
          </div>
          <div className="mt-3 flex gap-2">
            <button
              onClick={() => createMut.mutate({ name: newName, location: newLocation, notes: newNotes || undefined })}
              disabled={!newName.trim() || createMut.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-primary-950 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            >
              {createMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />} Start counting
            </button>
            {/* WEB-UIUX-1375: renamed from "Cancel" to "Discard" to disambiguate from the active-session cancel button */}
            <button
              onClick={() => setShowNew(false)}
              className="rounded-lg border border-surface-300 px-4 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-200 dark:hover:bg-surface-900"
            >
              Discard
            </button>
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-1 space-y-2">
          <h2 className="font-semibold text-sm uppercase text-surface-500">Sessions</h2>
          {/* WEB-UIUX-1367: session list filters — server accepts ?status= */}
          <div className="space-y-2">
            <input
              type="search"
              value={sessionSearch}
              onChange={(e) => setSessionSearch(e.target.value)}
              placeholder="Search name or location…"
              className="w-full rounded-md border border-surface-300 bg-white px-3 py-1.5 text-xs dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
              aria-label="Search stocktake sessions by name or location"
            />
            <select
              value={sessionStatusFilter}
              onChange={(e) => setSessionStatusFilter(e.target.value as '' | 'open' | 'committed' | 'cancelled')}
              aria-label="Filter stocktake sessions by status"
              className="w-full rounded-md border border-surface-300 bg-white px-3 py-1.5 text-xs dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
            >
              <option value="">All statuses</option>
              <option value="open">Open</option>
              <option value="committed">Committed</option>
              <option value="cancelled">Cancelled</option>
            </select>
          </div>
          {/* WEB-UIUX-1373: show skeleton rows while fetch is in-flight; only show empty state after resolve */}
          {sessionsIsPending && (
            <div className="space-y-2">
              {[0, 1, 2].map((i) => (
                <div key={i} className="w-full rounded-lg border border-surface-200 dark:border-surface-700 p-3 animate-pulse">
                  <div className="flex items-center justify-between">
                    <div className="h-4 w-32 rounded bg-surface-200 dark:bg-surface-700" />
                    <div className="h-4 w-14 rounded-full bg-surface-200 dark:bg-surface-700" />
                  </div>
                  <div className="mt-2 h-3 w-24 rounded bg-surface-100 dark:bg-surface-800" />
                </div>
              ))}
            </div>
          )}
          {!sessionsIsPending && sessions.length === 0 && (
            // WEB-UIUX-1374: onboarding nudge instead of bare "No sessions yet".
            <div className="rounded-lg border border-dashed border-surface-300 bg-surface-50 p-4 text-center dark:border-surface-700 dark:bg-surface-900/50">
              <p className="text-sm font-medium text-surface-700 dark:text-surface-200">
                {sessionStatusFilter || sessionSearch.trim() ? 'No sessions match those filters.' : 'No stocktakes yet'}
              </p>
              {!sessionStatusFilter && !sessionSearch.trim() && (
                <>
                  <p className="mt-1 text-xs text-surface-500 dark:text-surface-400">
                    A stocktake is a physical count session — scan items, compare against
                    `in_stock`, and commit the variance.
                  </p>
                  <button
                    type="button"
                    onClick={() => setShowNew(true)}
                    className="mt-3 inline-flex items-center gap-1 rounded-md bg-primary-600 px-3 py-1.5 text-xs font-semibold text-primary-950 hover:bg-primary-700"
                  >
                    Open your first stocktake
                  </button>
                </>
              )}
            </div>
          )}
          {sessions.map((s) => (
            <button
              key={s.id}
              onClick={() => setSelectedId(s.id)}
              className={cn(
                'w-full text-left rounded-lg border p-3 transition-colors',
                selectedId === s.id
                  // WEB-UIUX-1379: add dark-mode variants for selected card
                  ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/40 dark:border-primary-600'
                  : 'border-surface-200 hover:bg-surface-50 dark:border-surface-700 dark:hover:bg-surface-800',
              )}
            >
              <div className="flex items-center justify-between">
                <span className="font-medium">{s.name}</span>
                <span
                  className={cn(
                    'px-2 py-0.5 text-xs rounded-full',
                    // WEB-UIUX-1377: open uses primary (blue) instead of amber to avoid warning connotation
                    s.status === 'open' && 'bg-primary-100 text-primary-700 dark:bg-primary-900/30 dark:text-primary-300',
                    s.status === 'committed' && 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300',
                    s.status === 'cancelled' && 'bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-300',
                  )}
                >
                  {s.status}
                </span>
              </div>
              {s.location && <div className="text-xs text-surface-500">{s.location}</div>}
              <div className="text-xs text-surface-400 mt-1">
                {formatDateTime(s.opened_at)}
              </div>
              {/* WEB-UIUX-1362: progress preview so the operator returning to
                  a list of 5 open sessions sees where they got to without
                  drilling into each. Hidden for legacy rows that predate the
                  server-side hydration. */}
              {typeof s.items_counted === 'number' && (
                <div className="mt-1 flex items-center gap-2 text-xs text-surface-500 dark:text-surface-400">
                  <span>
                    {s.items_counted} counted
                  </span>
                  {typeof s.items_with_variance === 'number' && s.items_with_variance > 0 && (
                    <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-1.5 py-0.5 text-[10px] font-medium text-amber-700 dark:bg-amber-900/30 dark:text-amber-300">
                      {s.items_with_variance} variance
                    </span>
                  )}
                </div>
              )}
            </button>
          ))}
        </div>

        <div className="lg:col-span-2 space-y-4">
          {!detailData && (
            <div className="rounded-lg border border-dashed border-surface-300 p-8 text-center text-surface-400 dark:border-surface-700 dark:text-surface-500">
              Select a session to view counts
            </div>
          )}

          {detailData && (
            <>
              <div className="rounded-lg border border-surface-200 bg-white p-4 dark:bg-surface-800 dark:border-surface-700">
                <div className="flex items-start justify-between gap-3">
                  <h3 className="font-semibold text-lg">{detailData.session.name}</h3>
                  {/* WEB-UIUX-1366: CSV export for auditor handoff. Hits the
                      server route with a bearer-header request (no
                      window.open — that 401s in bearer-only tenants per
                      WEB-FD-021) and triggers a download. */}
                  <button
                    type="button"
                    onClick={async () => {
                      try {
                        const res = await api.get(`/stocktake/${detailData.session.id}.csv`, {
                          responseType: 'blob',
                        });
                        const blob = new Blob([res.data as BlobPart], { type: 'text/csv' });
                        const blobUrl = URL.createObjectURL(blob);
                        const a = document.createElement('a');
                        a.href = blobUrl;
                        const safeName = detailData.session.name.replace(/[^a-z0-9_\-]/gi, '_');
                        a.download = `stocktake_${safeName}_${detailData.session.id}.csv`;
                        document.body.appendChild(a);
                        a.click();
                        document.body.removeChild(a);
                        toast.success('Stocktake CSV downloaded');
                        setTimeout(() => URL.revokeObjectURL(blobUrl), 60_000);
                      } catch (err) {
                        console.error('[StocktakePage] CSV export failed', err);
                        toast.error('CSV export failed');
                      }
                    }}
                    title="Export counts as CSV for audit"
                    className="inline-flex items-center gap-1.5 rounded-md border border-surface-300 px-2.5 py-1 text-xs font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-200 dark:hover:bg-surface-700"
                  >
                    <Download className="h-3.5 w-3.5" /> Export CSV
                  </button>
                </div>
                <div className="mt-2 grid grid-cols-4 gap-3 text-sm">
                  <div>
                    <div className="text-surface-500">Items counted</div>
                    <div className="font-semibold text-lg">{detailData.summary.items_counted}</div>
                  </div>
                  <div>
                    <div className="text-surface-500">Variance items</div>
                    <div className="font-semibold text-lg">{detailData.summary.items_with_variance}</div>
                  </div>
                  <div>
                    <div className="text-surface-500">Shortage</div>
                    <div className="font-semibold text-lg text-red-600 dark:text-red-400">-{detailData.summary.shortage}</div>
                  </div>
                  <div>
                    <div className="text-surface-500">Surplus</div>
                    <div className="font-semibold text-lg text-green-600 dark:text-green-400">+{detailData.summary.surplus}</div>
                  </div>
                </div>
              </div>

              {/* WEB-UIUX-1363: read-only banner so a committed/cancelled
                  session doesn't render as "empty with no actions and no
                  context". */}
              {detailData.session.status !== 'open' && (
                <div className={cn(
                  'rounded-lg border p-3 text-sm',
                  detailData.session.status === 'committed'
                    ? 'border-green-300 bg-green-50 text-green-900 dark:border-green-700 dark:bg-green-900/30 dark:text-green-200'
                    : 'border-surface-300 bg-surface-50 text-surface-700 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300',
                )}>
                  <p className="font-medium">
                    Read-only — this session is {detailData.session.status}
                    {detailData.session.committed_at ? ` (${formatDateTime(detailData.session.committed_at)})` : ''}.
                  </p>
                  <p className="text-xs opacity-80 mt-1">
                    {detailData.session.status === 'committed'
                      ? 'Stock adjustments have been applied to inventory; counts cannot be re-edited.'
                      : 'No stock changes were applied. Open a new stocktake to start over.'}
                  </p>
                </div>
              )}

              {detailData.session.status === 'open' && (
                <div className="rounded-lg border border-surface-200 bg-white p-4 dark:bg-surface-800 dark:border-surface-700">
                  <h3 className="font-semibold mb-3 flex items-center gap-2">
                    <ScanBarcode className="h-4 w-4" /> Scan / enter SKU
                  </h3>
                  <form onSubmit={handleScan} className="space-y-2">
                    <div className="flex gap-2">
                      <input
                        ref={scanRef}
                        value={scanInput}
                        onChange={(e) => setScanInput(e.target.value)}
                        placeholder="Scan barcode or type SKU..."
                        className="flex-1 rounded-md border border-surface-300 bg-white px-3 py-2 text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 dark:placeholder:text-surface-500"
                      />
                      <input
                        value={manualCountedQty}
                        onChange={(e) => setManualCountedQty(e.target.value)}
                        placeholder="Qty (blank = +1)"
                        type="number"
                        className="w-32 rounded-md border border-surface-300 bg-white px-3 py-2 text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 dark:placeholder:text-surface-500"
                      />
                      <button
                        type="submit"
                        className="rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-primary-950"
                      >
                        Count
                      </button>
                    </div>
                    {/* WEB-UIUX-1357: per-count note (e.g. "surplus from open box")
                        so the auditor can reconstruct unusual variances. */}
                    <input
                      value={scanNote}
                      onChange={(e) => setScanNote(e.target.value)}
                      placeholder="Note for this count (optional — explains variance)"
                      maxLength={500}
                      className="w-full rounded-md border border-surface-300 bg-white px-3 py-2 text-xs text-surface-700 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-300 dark:placeholder:text-surface-500"
                    />
                  </form>

                  <p className="mt-3 text-xs text-surface-500 dark:text-surface-400">
                    To correct a count, re-scan the item and enter the right quantity — the previous row is overwritten automatically.
                  </p>

                  {/* WEB-UIUX-1372: blocking overlay while commit is in-flight */}
                  {commitMut.isPending && (
                    <div className="mt-4 rounded-lg bg-surface-900/70 dark:bg-black/60 px-4 py-3 flex items-center gap-3 text-white text-sm font-medium">
                      <Loader2 className="h-4 w-4 animate-spin shrink-0" />
                      Committing {detailData.counts.length} count{detailData.counts.length !== 1 ? 's' : ''}…
                    </div>
                  )}

                  {/* WEB-UIUX-1370: commit/cancel only visible to admin + manager */}
                  {['admin', 'manager'].includes(user?.role ?? '') && (
                  <div className="mt-4 flex gap-2">
                    <button
                      onClick={async () => {
                        const { items_counted, items_with_variance, shortage, surplus } = detailData.summary;
                        const netDelta = surplus - shortage;

                        // Build diff list: counts where variance !== 0, capped at 10 visible rows
                        const changedCounts = detailData.counts.filter((c) => c.variance !== 0);
                        const MAX_ROWS = 10;
                        const visibleRows = changedCounts.slice(0, MAX_ROWS);
                        const hiddenCount = changedCounts.length - visibleRows.length;

                        // Dollar impact per row: variance × cost_price (may be 0 if unknown)
                        const totalDollarImpact = changedCounts.reduce(
                          (sum, c) => sum + c.variance * (c.cost_price ?? 0),
                          0,
                        );

                        const diffNode = (
                          <div className="space-y-3">
                            {changedCounts.length > 0 ? (
                              <>
                                <div className="max-h-48 overflow-y-auto rounded border border-surface-200 dark:border-surface-700 text-sm">
                                  <table className="w-full">
                                    <thead className="bg-surface-50 dark:bg-surface-900 sticky top-0">
                                      <tr>
                                        <th className="text-left px-3 py-1.5 font-medium text-surface-600 dark:text-surface-400">Item</th>
                                        <th className="text-right px-3 py-1.5 font-medium text-surface-600 dark:text-surface-400">Δ Qty</th>
                                        <th className="text-right px-3 py-1.5 font-medium text-surface-600 dark:text-surface-400">Δ Cost</th>
                                      </tr>
                                    </thead>
                                    <tbody>
                                      {visibleRows.map((c) => {
                                        const dollarImpact = c.variance * (c.cost_price ?? 0);
                                        return (
                                          <tr key={c.id} className="border-t border-surface-100 dark:border-surface-700">
                                            <td className="px-3 py-1.5">
                                              <span className="font-medium">{c.name ?? `#${c.inventory_item_id}`}</span>
                                              {c.sku && <span className="ml-1 text-xs text-surface-400">{c.sku}</span>}
                                            </td>
                                            <td className={`text-right px-3 py-1.5 font-mono font-semibold ${c.variance > 0 ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}`}>
                                              {c.variance > 0 ? '+' : ''}{c.variance}
                                            </td>
                                            <td className={`text-right px-3 py-1.5 font-mono text-xs ${dollarImpact >= 0 ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}`}>
                                              {c.cost_price != null
                                                ? (dollarImpact >= 0 ? '+' : '') + formatCurrency(dollarImpact)
                                                : '—'}
                                            </td>
                                          </tr>
                                        );
                                      })}
                                      {hiddenCount > 0 && (
                                        <tr className="border-t border-surface-100 dark:border-surface-700">
                                          <td colSpan={3} className="px-3 py-1.5 text-xs text-surface-400 italic">
                                            …and {hiddenCount} more item{hiddenCount !== 1 ? 's' : ''} with variance
                                          </td>
                                        </tr>
                                      )}
                                    </tbody>
                                  </table>
                                </div>
                                <div className="flex justify-between text-sm font-semibold">
                                  <span>{items_with_variance} item{items_with_variance !== 1 ? 's' : ''} changing · net {netDelta >= 0 ? '+' : ''}{netDelta} units</span>
                                  {totalDollarImpact !== 0 && (
                                    <span className={totalDollarImpact >= 0 ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}>
                                      {totalDollarImpact >= 0 ? '+' : ''}{formatCurrency(totalDollarImpact)} cost impact
                                    </span>
                                  )}
                                </div>
                              </>
                            ) : (
                              <p className="text-sm text-surface-500">
                                {items_counted} item{items_counted !== 1 ? 's' : ''} counted — no variances detected.
                              </p>
                            )}
                            <p className="text-sm text-surface-600 dark:text-surface-400 border-t border-surface-200 dark:border-surface-700 pt-2">
                              This action is irreversible. Stock levels will be updated immediately.
                            </p>
                          </div>
                        );

                        // WEB-UIUX-1369: Commit is the irreversible org-wide
                        // write — danger-gate the confirm + a strong red ramp.
                        const ok = await useConfirmStore.getState().confirm({
                          message: diffNode,
                          title: 'Commit stocktake?',
                          confirmLabel: 'Commit — rewrite stock',
                          danger: true,
                        });
                        if (ok) commitMut.mutate();
                      }}
                      disabled={detailData.counts.length === 0 || commitMut.isPending}
                      // WEB-UIUX-1369: red ramp matches the destructive
                      // write semantics. Cancel/Abandon now wears the
                      // neutral outline (safe abort).
                      className="inline-flex items-center gap-2 rounded-lg bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
                    >
                      <Check className="h-4 w-4" /> Commit ({detailData.counts.length})
                    </button>
                    {/* WEB-UIUX-1375: renamed from "Cancel" to "Abandon stocktake" to disambiguate from the new-session Discard button */}
                    {/* WEB-UIUX-1355: typed-confirm on Abandon since Cancelled
                        is terminal — there is no /restore endpoint. Operator
                        on a 200-row count needs an explicit verbal gate before
                        every line is lost. */}
                    <button
                      onClick={async () => {
                        const lineCount = detailData.counts.length;
                        // First confirm — surfaces blast radius.
                        const first = await useConfirmStore.getState().confirm({
                          message: lineCount > 0
                            ? `Abandon this stocktake? ${lineCount} counted line${lineCount === 1 ? '' : 's'} will be discarded permanently — there is no restore.`
                            : 'Abandon this stocktake? No stock changes will be applied.',
                          title: 'Abandon stocktake?',
                          confirmLabel: 'Abandon stocktake',
                          danger: true,
                        });
                        if (!first) return;
                        // Double-confirm only when there's actual count work
                        // at risk (>= 1 line). Empty stocktakes skip the
                        // second prompt to avoid annoying the legit
                        // "I started this by mistake" case.
                        if (lineCount > 0) {
                          const second = await useConfirmStore.getState().confirm({
                            message: `This is permanent. ${lineCount} counted line${lineCount === 1 ? '' : 's'} cannot be recovered after abandoning. Continue?`,
                            title: 'Confirm abandon',
                            confirmLabel: 'Yes, discard counts',
                            danger: true,
                          });
                          if (!second) return;
                        }
                        cancelMut.mutate();
                      }}
                      // WEB-UIUX-1369: neutral outline since Abandon is the
                      // safe abort (no stock writes); Commit owns the red ramp.
                      className="inline-flex items-center gap-2 rounded-lg border border-surface-300 px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-800"
                    >
                      <X className="h-4 w-4" /> Abandon stocktake
                    </button>
                  </div>
                  )} {/* end WEB-UIUX-1370 role gate */}
                </div>
              )}

              {/* WEB-UIUX-1365: search/filter for large sessions. */}
              <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
                <input
                  type="search"
                  value={countsSearch}
                  onChange={(e) => setCountsSearch(e.target.value)}
                  placeholder="Search SKU or name…"
                  className="flex-1 rounded-md border border-surface-300 bg-white px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                  aria-label="Filter counts by SKU or item name"
                />
                <select
                  value={varianceFilter}
                  onChange={(e) => setVarianceFilter(e.target.value as 'all' | 'variance' | 'shortage' | 'surplus' | 'match')}
                  aria-label="Filter counts by variance type"
                  className="rounded-md border border-surface-300 bg-white px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                >
                  <option value="all">All counts</option>
                  <option value="variance">Any variance (≠ 0)</option>
                  <option value="shortage">Shortage (variance &lt; 0)</option>
                  <option value="surplus">Surplus (variance &gt; 0)</option>
                  <option value="match">Match (variance = 0)</option>
                </select>
                <span className="text-xs text-surface-500 whitespace-nowrap">
                  {filteredCounts.length} of {detailData.counts.length}
                </span>
              </div>

              <div className="rounded-lg border border-surface-200 bg-white overflow-x-auto dark:bg-surface-800 dark:border-surface-700">
                <table className="w-full text-sm">
                  <thead className="bg-surface-50 border-b border-surface-200 dark:bg-surface-900 dark:border-surface-700">
                    <tr>
                      <th className="text-left px-3 py-2">Item</th>
                      <th className="text-right px-3 py-2">Expected</th>
                      <th className="text-right px-3 py-2">Counted</th>
                      <th className="text-right px-3 py-2">Variance</th>
                      <th className="text-left px-3 py-2">When <span className="font-normal text-surface-400">(re-scan to update)</span></th>
                      {detailData.session.status === 'open' && <th className="px-3 py-2 w-12 sr-only">Actions</th>}
                    </tr>
                  </thead>
                  <tbody>
                    {filteredCounts.map((c) => (
                      <tr key={c.id} className="border-b border-surface-100 last:border-0 dark:border-surface-700">
                        <td className="px-3 py-2">
                          <div className="font-medium">{c.name}</div>
                          <div className="text-xs text-surface-500">{c.sku}</div>
                        </td>
                        <td className="text-right px-3 py-2">
                          {c.expected_qty}
                          {/* WEB-UIUX-1356: warn when the baseline this row
                              was scanned against has drifted from live
                              in_stock (concurrent sales between scan and
                              now). Tooltip names the live value so the
                              operator can decide whether to re-scan. */}
                          {typeof c.current_in_stock === 'number'
                            && c.current_in_stock !== c.expected_qty && (
                            <span
                              title={`Baseline drifted — current in_stock is ${c.current_in_stock}. Re-scan to refresh.`}
                              aria-label={`Baseline drifted; current in_stock is ${c.current_in_stock}`}
                              className="ml-1 inline-flex items-center justify-center rounded-full bg-amber-100 px-1.5 text-[10px] font-semibold text-amber-700 dark:bg-amber-900/30 dark:text-amber-300"
                            >
                              !
                            </span>
                          )}
                        </td>
                        <td className="text-right px-3 py-2">{c.counted_qty}</td>
                        <td
                          className={cn(
                            'text-right px-3 py-2 font-semibold',
                            c.variance > 0 && 'text-green-600 dark:text-green-400',
                            c.variance < 0 && 'text-red-600 dark:text-red-400',
                          )}
                        >
                          {c.variance > 0 ? '+' : ''}
                          {c.variance}
                        </td>
                        <td className="px-3 py-2 text-xs text-surface-500">
                          {formatDateTime(c.counted_at)}
                        </td>
                        {detailData.session.status === 'open' && (
                          <td className="px-3 py-2 text-right">
                            <button
                              type="button"
                              onClick={() => {
                                if (window.confirm(`Remove "${c.name ?? `#${c.inventory_item_id}`}" from this stocktake?`)) {
                                  deleteCountMut.mutate(c.inventory_item_id);
                                }
                              }}
                              disabled={deleteCountMut.isPending}
                              aria-label={`Remove ${c.name ?? `item #${c.inventory_item_id}`} from stocktake`}
                              title="Remove this row (typo cleanup)"
                              className="rounded p-1 text-surface-400 hover:bg-red-50 hover:text-red-600 disabled:opacity-50 dark:hover:bg-red-900/20"
                            >
                              <X className="h-4 w-4" />
                            </button>
                          </td>
                        )}
                      </tr>
                    ))}
                    {detailData.counts.length === 0 && (
                      <tr>
                        <td colSpan={5} className="px-3 py-8 text-center text-surface-400">
                          No counts yet — scan an item to start
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
