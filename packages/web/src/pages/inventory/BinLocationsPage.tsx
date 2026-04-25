/**
 * Bin locations + heatmap page.
 *
 * Two columns:
 *   Left — CRUD list of bins (add, edit, deactivate).
 *   Right — heatmap grid colored by pick frequency, with re-layout suggestions.
 *
 * Cross-ref: criticalaudit.md §48 idea #2.
 */
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ChevronLeft, MapPin, Plus, Flame, Loader2, Trash2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { cn } from '@/utils/cn';

interface BinLocation {
  id: number;
  code: string;
  description: string | null;
  aisle: string | null;
  shelf: string | null;
  bin: string | null;
  is_active: number;
}

interface HeatmapBin {
  bin_id: number;
  code: string;
  picks: number;
  items_tracked: number;
  aisle: string | null;
  shelf: string | null;
  heat: number;
}

interface HeatmapResponse {
  window_days: number;
  bins: HeatmapBin[];
  suggestions: Array<{ bin_code: string; reason: string; picks: number; recommendation: string }>;
  max_picks: number;
}

export function BinLocationsPage() {
  const queryClient = useQueryClient();
  const [showNew, setShowNew] = useState(false);
  const [newCode, setNewCode] = useState('');
  const [newDescription, setNewDescription] = useState('');
  const [newAisle, setNewAisle] = useState('');
  const [newShelf, setNewShelf] = useState('');
  const [newBin, setNewBin] = useState('');
  const [windowDays, setWindowDays] = useState(90);

  const { data: binsData } = useQuery({
    queryKey: ['bin-locations'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: BinLocation[] }>(
        '/inventory-enrich/bin-locations',
      );
      return res.data.data;
    },
  });
  const bins: BinLocation[] = binsData || [];

  const { data: heatmapData } = useQuery({
    queryKey: ['bin-heatmap', windowDays],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: HeatmapResponse }>(
        `/inventory-enrich/bin-locations/heatmap?days=${windowDays}`,
      );
      return res.data.data;
    },
  });

  const createMut = useMutation({
    mutationFn: async () => {
      const res = await api.post('/inventory-enrich/bin-locations', {
        code: newCode,
        description: newDescription || null,
        aisle: newAisle || null,
        shelf: newShelf || null,
        bin: newBin || null,
      });
      return res.data.data;
    },
    onSuccess: () => {
      toast.success('Bin created');
      queryClient.invalidateQueries({ queryKey: ['bin-locations'] });
      queryClient.invalidateQueries({ queryKey: ['bin-heatmap'] });
      setShowNew(false);
      setNewCode('');
      setNewDescription('');
      setNewAisle('');
      setNewShelf('');
      setNewBin('');
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to create bin'),
  });

  const deleteMut = useMutation({
    mutationFn: async (id: number) => {
      await api.delete(`/inventory-enrich/bin-locations/${id}`);
    },
    onSuccess: () => {
      toast.success('Bin deactivated');
      queryClient.invalidateQueries({ queryKey: ['bin-locations'] });
    },
  });

  const heatColor = (heat: number) => {
    // WEB-FB-020: dark-mode partners for the cool side of the ramp so heatmap
    // tiles remain visible on dark theme (brand surface ramp alignment).
    if (heat > 0.8) return 'bg-red-500 text-white';
    if (heat > 0.6) return 'bg-orange-500 text-white';
    if (heat > 0.4) return 'bg-amber-400 dark:bg-amber-500 dark:text-surface-900';
    if (heat > 0.2) return 'bg-yellow-200 dark:bg-yellow-700/60 dark:text-yellow-50';
    if (heat > 0) return 'bg-surface-100 dark:bg-surface-800 dark:text-surface-200';
    return 'bg-surface-50 text-surface-400 dark:bg-surface-900 dark:text-surface-500';
  };

  return (
    <div className="space-y-6">
      <div>
        <Link to="/inventory" className="text-sm text-primary-600 hover:underline inline-flex items-center gap-1">
          <ChevronLeft className="h-4 w-4" /> Back to Inventory
        </Link>
        <h1 className="text-2xl font-bold mt-2 flex items-center gap-2">
          <MapPin className="h-6 w-6" /> Bin Locations
        </h1>
        <p className="text-sm text-surface-500">Register bins and visualize pick activity</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-1 space-y-3">
          <div className="flex items-center justify-between">
            <h2 className="font-semibold">Bins ({bins.length})</h2>
            <button
              onClick={() => setShowNew(true)}
              className="inline-flex items-center gap-1 rounded-md bg-primary-600 px-3 py-1 text-xs font-semibold text-white"
            >
              <Plus className="h-3 w-3" /> Add
            </button>
          </div>

          {showNew && (
            <div className="rounded-lg border border-surface-200 bg-white p-3 space-y-2">
              <input
                value={newCode}
                onChange={(e) => setNewCode(e.target.value.toUpperCase())}
                placeholder="Code (e.g. A1-S2-B3)"
                className="w-full rounded border border-surface-300 px-2 py-1 text-sm"
              />
              <input
                value={newDescription}
                onChange={(e) => setNewDescription(e.target.value)}
                placeholder="Description"
                className="w-full rounded border border-surface-300 px-2 py-1 text-sm"
              />
              <div className="grid grid-cols-3 gap-1">
                <input
                  value={newAisle}
                  onChange={(e) => setNewAisle(e.target.value)}
                  placeholder="Aisle"
                  className="rounded border border-surface-300 px-2 py-1 text-xs"
                />
                <input
                  value={newShelf}
                  onChange={(e) => setNewShelf(e.target.value)}
                  placeholder="Shelf"
                  className="rounded border border-surface-300 px-2 py-1 text-xs"
                />
                <input
                  value={newBin}
                  onChange={(e) => setNewBin(e.target.value)}
                  placeholder="Bin"
                  className="rounded border border-surface-300 px-2 py-1 text-xs"
                />
              </div>
              <div className="flex gap-1">
                <button
                  onClick={() => createMut.mutate()}
                  disabled={!newCode.trim() || createMut.isPending}
                  className="flex-1 rounded bg-primary-600 px-2 py-1 text-xs font-semibold text-white disabled:opacity-50"
                >
                  {createMut.isPending && <Loader2 className="inline h-3 w-3 animate-spin mr-1" />}
                  Create
                </button>
                <button
                  onClick={() => setShowNew(false)}
                  className="rounded border border-surface-300 px-2 py-1 text-xs"
                >
                  Cancel
                </button>
              </div>
            </div>
          )}

          <div className="space-y-1 max-h-[60vh] overflow-y-auto">
            {bins.map((b) => (
              <div key={b.id} className="flex items-center justify-between rounded border border-surface-200 bg-white px-3 py-2">
                <div>
                  <div className="font-mono text-sm">{b.code}</div>
                  {b.description && <div className="text-xs text-surface-500">{b.description}</div>}
                </div>
                <button
                  onClick={() => {
                    if (confirm(`Deactivate bin ${b.code}?`)) deleteMut.mutate(b.id);
                  }}
                  className="text-red-500 hover:text-red-700 disabled:opacity-40"
                  disabled={deleteMut.isPending && deleteMut.variables === b.id}
                  aria-label={`Deactivate bin ${b.code}`}
                >
                  <Trash2 className="h-3 w-3" />
                </button>
              </div>
            ))}
          </div>
        </div>

        <div className="lg:col-span-2 space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="font-semibold flex items-center gap-2">
              <Flame className="h-5 w-5 text-orange-500" /> Pick Heatmap
            </h2>
            <select
              value={windowDays}
              onChange={(e) => setWindowDays(parseInt(e.target.value, 10))}
              className="rounded-md border border-surface-300 px-2 py-1 text-sm"
            >
              <option value={30}>Last 30 days</option>
              <option value={90}>Last 90 days</option>
              <option value={180}>Last 180 days</option>
              <option value={365}>Last year</option>
            </select>
          </div>

          <div className="rounded-lg border border-surface-200 bg-white p-4">
            {heatmapData && heatmapData.bins.length > 0 ? (
              <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 gap-2">
                {heatmapData.bins.map((b) => (
                  <div
                    key={b.bin_id}
                    className={cn(
                      'aspect-square rounded flex flex-col items-center justify-center text-xs p-1',
                      heatColor(b.heat),
                    )}
                  >
                    <div className="font-mono font-bold">{b.code}</div>
                    <div className="opacity-80">{b.picks} picks</div>
                    <div className="opacity-60 text-[10px]">{b.items_tracked} items</div>
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-sm text-surface-400 text-center py-8">
                No heatmap data — assign items to bins first
              </p>
            )}
          </div>

          {heatmapData && heatmapData.suggestions.length > 0 && (
            <div className="rounded-lg border border-amber-200 bg-amber-50 p-4">
              <h3 className="font-semibold text-amber-800 mb-2">Re-layout suggestions</h3>
              <ul className="text-sm text-amber-900 space-y-1">
                {heatmapData.suggestions.map((s, i) => (
                  <li key={i}>
                    Bin <span className="font-mono font-bold">{s.bin_code}</span> has {s.picks} picks —
                    move closer to the bench
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
