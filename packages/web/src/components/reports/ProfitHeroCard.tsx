/**
 * ProfitHeroCard — the #1 KPI tile on the dashboard (audit 47.1)
 *
 * Shows 30-day gross margin with a zone color driven by owner-configured
 * thresholds. Green >= 50% (default), amber >= 30% (default), red below.
 * Owners can toggle the thresholds in place.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { TrendingUp, Settings, Check, X } from 'lucide-react';
import { reportApi } from '@/api/endpoints';
import { formatCurrency } from '@/utils/format';
import { cn } from '@/utils/cn';

// RPT-HERO2: zone may be 'unknown' when revenue is 0 (no data yet). The UI
// renders that state as neutral grey with a "no data" label instead of the
// red zone, matching the new server contract that returns null margin.
type Zone = 'green' | 'amber' | 'red' | 'unknown';

interface ProfitHeroData {
  gross_margin_pct: number | null;
  gross_profit: number;
  revenue: number;
  cogs: number;
  zone: Zone;
  thresholds: { green: number; amber: number };
  period_label: string;
  period_days: number;
}

const ZONE_STYLES: Record<Zone, string> = {
  green: 'bg-green-500 text-white border-green-600',
  amber: 'bg-amber-400 text-black border-amber-500',
  red: 'bg-red-500 text-white border-red-600',
  unknown: 'bg-gray-200 text-gray-800 border-gray-300',
};

const ZONE_LABELS: Record<Zone, string> = {
  green: 'Healthy margin',
  amber: 'Margin under pressure',
  red: 'Margin is tight',
  unknown: 'No revenue recorded yet',
};

export function ProfitHeroCard() {
  const qc = useQueryClient();
  const [editOpen, setEditOpen] = useState(false);
  const [greenInput, setGreenInput] = useState('');
  const [amberInput, setAmberInput] = useState('');

  const { data, isLoading, error } = useQuery({
    queryKey: ['reports', 'profit-hero'],
    queryFn: async () => {
      const res = await reportApi.profitHero();
      return res.data.data as ProfitHeroData;
    },
    refetchInterval: 60_000,
  });

  const updateMutation = useMutation({
    mutationFn: (payload: { green: number; amber: number }) =>
      reportApi.updateProfitThresholds(payload),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['reports', 'profit-hero'] });
      setEditOpen(false);
    },
  });

  const openEditor = () => {
    if (!data) return;
    setGreenInput(String(data.thresholds.green));
    setAmberInput(String(data.thresholds.amber));
    setEditOpen(true);
  };

  const saveThresholds = () => {
    const green = Number(greenInput);
    const amber = Number(amberInput);
    if (!Number.isFinite(green) || !Number.isFinite(amber)) return;
    if (green <= amber) return;
    updateMutation.mutate({ green, amber });
  };

  if (isLoading) {
    return (
      <div className="h-40 rounded-2xl border-2 border-dashed border-gray-300 animate-pulse bg-gray-50" />
    );
  }

  if (error || !data) {
    return (
      <div className="h-40 rounded-2xl border-2 border-red-300 bg-red-50 p-6 text-red-700">
        Could not load profit KPI.
      </div>
    );
  }

  const zoneStyle = ZONE_STYLES[data.zone];

  return (
    <div className={cn('relative rounded-2xl border-2 p-6 shadow-lg', zoneStyle)}>
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-2 text-sm font-semibold uppercase tracking-wide opacity-80">
          <TrendingUp size={16} />
          Gross Margin {data.period_label}
        </div>
        <button
          type="button"
          onClick={openEditor}
          className="opacity-70 hover:opacity-100 transition"
          title="Edit zone thresholds"
        >
          <Settings size={18} />
        </button>
      </div>

      <div className="mt-3 flex items-baseline gap-4">
        <div className="text-5xl font-black tabular-nums">
          {data.gross_margin_pct == null ? '—' : `${data.gross_margin_pct.toFixed(1)}%`}
        </div>
        <div className="text-lg font-medium opacity-90">
          {formatCurrency(data.gross_profit)} profit
        </div>
      </div>

      <div className="mt-2 text-sm opacity-85">
        {ZONE_LABELS[data.zone]} · Revenue {formatCurrency(data.revenue)} · COGS {formatCurrency(data.cogs)}
      </div>

      <div className="mt-3 text-xs opacity-70">
        Green &ge; {data.thresholds.green}% &middot; Amber &ge; {data.thresholds.amber}% &middot; Red below
      </div>

      {editOpen && (
        <div
          className="absolute inset-0 rounded-2xl bg-black/70 p-6 flex flex-col justify-center backdrop-blur-sm z-10"
          role="dialog"
          aria-label="Edit profit thresholds"
        >
          <div className="text-white font-semibold mb-3">Adjust zone thresholds</div>
          <div className="grid grid-cols-2 gap-3">
            <label className="flex flex-col text-xs text-white/80">
              Green &ge;
              <input
                type="number"
                min={0}
                max={100}
                value={greenInput}
                onChange={e => setGreenInput(e.target.value)}
                className="mt-1 rounded-md border border-white/30 bg-white/10 px-2 py-1 text-white"
              />
            </label>
            <label className="flex flex-col text-xs text-white/80">
              Amber &ge;
              <input
                type="number"
                min={0}
                max={100}
                value={amberInput}
                onChange={e => setAmberInput(e.target.value)}
                className="mt-1 rounded-md border border-white/30 bg-white/10 px-2 py-1 text-white"
              />
            </label>
          </div>
          <div className="mt-4 flex gap-2">
            <button
              type="button"
              onClick={saveThresholds}
              disabled={updateMutation.isPending}
              className="flex items-center gap-1 rounded-md bg-green-500 px-3 py-1.5 text-sm text-white hover:bg-green-600 disabled:opacity-50"
            >
              <Check size={14} /> Save
            </button>
            <button
              type="button"
              onClick={() => setEditOpen(false)}
              className="flex items-center gap-1 rounded-md bg-white/20 px-3 py-1.5 text-sm text-white hover:bg-white/30"
            >
              <X size={14} /> Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
