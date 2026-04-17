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
import { Link } from 'react-router-dom';
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
} from 'lucide-react';
import { api } from '@/api/client';
import { cn } from '@/utils/cn';

interface StocktakeSession {
  id: number;
  name: string;
  location: string | null;
  status: 'open' | 'committed' | 'cancelled';
  opened_at: string;
  committed_at: string | null;
  notes: string | null;
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
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [showNew, setShowNew] = useState(false);
  const [newName, setNewName] = useState('');
  const [newLocation, setNewLocation] = useState('');
  const [scanInput, setScanInput] = useState('');
  const [manualCountedQty, setManualCountedQty] = useState('');
  const scanRef = useRef<HTMLInputElement>(null);

  const { data: sessionsData } = useQuery({
    queryKey: ['stocktakes'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: StocktakeSession[] }>('/stocktake');
      return res.data.data;
    },
  });
  const sessions: StocktakeSession[] = sessionsData || [];

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

  useEffect(() => {
    if (detailData?.session.status === 'open') {
      scanRef.current?.focus();
    }
  }, [detailData?.session.status, detailData?.counts.length]);

  const createMut = useMutation({
    mutationFn: async (body: { name: string; location: string }) => {
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
      setSelectedId(session.id);
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to open session'),
  });

  const scanMut = useMutation({
    mutationFn: async (body: { inventory_item_id: number; counted_qty: number }) => {
      const res = await api.post(`/stocktake/${selectedId}/counts`, body);
      return res.data.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['stocktake', selectedId] });
      setScanInput('');
      setManualCountedQty('');
      scanRef.current?.focus();
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Scan failed'),
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
    // Look up the item by SKU/UPC via the existing inventory list endpoint.
    try {
      const res = await api.get('/inventory', { params: { keyword: q, pagesize: 1 } });
      const items = res.data.data?.items || [];
      if (items.length === 0) {
        toast.error(`No item matching "${q}"`);
        return;
      }
      const item = items[0];
      const counted = manualCountedQty
        ? parseInt(manualCountedQty, 10)
        : item.in_stock + 1; // quick-scan default: increment
      scanMut.mutate({ inventory_item_id: item.id, counted_qty: counted });
    } catch (err: any) {
      toast.error(err?.response?.data?.message || 'Lookup failed');
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <Link to="/inventory" className="text-sm text-primary-600 hover:underline inline-flex items-center gap-1">
            <ChevronLeft className="h-4 w-4" /> Back to Inventory
          </Link>
          <h1 className="text-2xl font-bold mt-2 flex items-center gap-2">
            <ClipboardList className="h-6 w-6" /> Stocktakes
          </h1>
          <p className="text-sm text-surface-500">Physical count sessions with variance tracking</p>
        </div>
        <button
          onClick={() => setShowNew(true)}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-white hover:bg-primary-700"
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
              className="rounded-md border border-surface-300 px-3 py-2 text-sm"
            />
            <input
              value={newLocation}
              onChange={(e) => setNewLocation(e.target.value)}
              placeholder="Location (optional)"
              className="rounded-md border border-surface-300 px-3 py-2 text-sm"
            />
          </div>
          <div className="mt-3 flex gap-2">
            <button
              onClick={() => createMut.mutate({ name: newName, location: newLocation })}
              disabled={!newName.trim() || createMut.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
            >
              {createMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />} Open
            </button>
            <button
              onClick={() => setShowNew(false)}
              className="rounded-lg border border-surface-300 px-4 py-2 text-sm"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-1 space-y-2">
          <h2 className="font-semibold text-sm uppercase text-surface-500">Sessions</h2>
          {sessions.length === 0 && (
            <p className="text-sm text-surface-400">No sessions yet</p>
          )}
          {sessions.map((s) => (
            <button
              key={s.id}
              onClick={() => setSelectedId(s.id)}
              className={cn(
                'w-full text-left rounded-lg border p-3 transition-colors',
                selectedId === s.id
                  ? 'border-primary-500 bg-primary-50'
                  : 'border-surface-200 hover:bg-surface-50',
              )}
            >
              <div className="flex items-center justify-between">
                <span className="font-medium">{s.name}</span>
                <span
                  className={cn(
                    'px-2 py-0.5 text-xs rounded-full',
                    s.status === 'open' && 'bg-amber-100 text-amber-700',
                    s.status === 'committed' && 'bg-green-100 text-green-700',
                    s.status === 'cancelled' && 'bg-surface-100 text-surface-500',
                  )}
                >
                  {s.status}
                </span>
              </div>
              {s.location && <div className="text-xs text-surface-500">{s.location}</div>}
              <div className="text-xs text-surface-400 mt-1">
                {new Date(s.opened_at).toLocaleString()}
              </div>
            </button>
          ))}
        </div>

        <div className="lg:col-span-2 space-y-4">
          {!detailData && (
            <div className="rounded-lg border border-dashed border-surface-300 p-8 text-center text-surface-400">
              Select a session to view counts
            </div>
          )}

          {detailData && (
            <>
              <div className="rounded-lg border border-surface-200 bg-white p-4">
                <h3 className="font-semibold text-lg">{detailData.session.name}</h3>
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
                    <div className="font-semibold text-lg text-red-600">-{detailData.summary.shortage}</div>
                  </div>
                  <div>
                    <div className="text-surface-500">Surplus</div>
                    <div className="font-semibold text-lg text-green-600">+{detailData.summary.surplus}</div>
                  </div>
                </div>
              </div>

              {detailData.session.status === 'open' && (
                <div className="rounded-lg border border-surface-200 bg-white p-4">
                  <h3 className="font-semibold mb-3 flex items-center gap-2">
                    <ScanBarcode className="h-4 w-4" /> Scan / enter SKU
                  </h3>
                  <form onSubmit={handleScan} className="flex gap-2">
                    <input
                      ref={scanRef}
                      value={scanInput}
                      onChange={(e) => setScanInput(e.target.value)}
                      placeholder="Scan barcode or type SKU..."
                      className="flex-1 rounded-md border border-surface-300 px-3 py-2"
                    />
                    <input
                      value={manualCountedQty}
                      onChange={(e) => setManualCountedQty(e.target.value)}
                      placeholder="Qty (blank = +1)"
                      type="number"
                      className="w-32 rounded-md border border-surface-300 px-3 py-2"
                    />
                    <button
                      type="submit"
                      className="rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-white"
                    >
                      Count
                    </button>
                  </form>

                  <div className="mt-4 flex gap-2">
                    <button
                      onClick={() => {
                        if (confirm('Commit this stocktake? Inventory counts will be updated.')) {
                          commitMut.mutate();
                        }
                      }}
                      disabled={detailData.counts.length === 0 || commitMut.isPending}
                      className="inline-flex items-center gap-2 rounded-lg bg-green-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
                    >
                      <Check className="h-4 w-4" /> Commit ({detailData.counts.length})
                    </button>
                    <button
                      onClick={() => {
                        if (confirm('Cancel this stocktake? No stock changes will be applied.')) {
                          cancelMut.mutate();
                        }
                      }}
                      className="inline-flex items-center gap-2 rounded-lg border border-red-300 px-4 py-2 text-sm font-semibold text-red-600"
                    >
                      <X className="h-4 w-4" /> Cancel
                    </button>
                  </div>
                </div>
              )}

              <div className="rounded-lg border border-surface-200 bg-white overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-surface-50 border-b border-surface-200">
                    <tr>
                      <th className="text-left px-3 py-2">Item</th>
                      <th className="text-right px-3 py-2">Expected</th>
                      <th className="text-right px-3 py-2">Counted</th>
                      <th className="text-right px-3 py-2">Variance</th>
                      <th className="text-left px-3 py-2">When</th>
                    </tr>
                  </thead>
                  <tbody>
                    {detailData.counts.map((c) => (
                      <tr key={c.id} className="border-b border-surface-100 last:border-0">
                        <td className="px-3 py-2">
                          <div className="font-medium">{c.name}</div>
                          <div className="text-xs text-surface-500">{c.sku}</div>
                        </td>
                        <td className="text-right px-3 py-2">{c.expected_qty}</td>
                        <td className="text-right px-3 py-2">{c.counted_qty}</td>
                        <td
                          className={cn(
                            'text-right px-3 py-2 font-semibold',
                            c.variance > 0 && 'text-green-600',
                            c.variance < 0 && 'text-red-600',
                          )}
                        >
                          {c.variance > 0 ? '+' : ''}
                          {c.variance}
                        </td>
                        <td className="px-3 py-2 text-xs text-surface-500">
                          {new Date(c.counted_at).toLocaleTimeString()}
                        </td>
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
