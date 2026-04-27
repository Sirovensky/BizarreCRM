/**
 * ABC analysis — top sellers vs dead stock with clearance suggestions.
 *
 * Cross-ref: criticalaudit.md §48 idea #7.
 */
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ChevronLeft, TrendingUp, Skull, Download, Tag, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { inventoryApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatCurrency } from '@/utils/format';

interface AbcItem {
  id: number;
  name: string;
  sku: string | null;
  in_stock: number;
  cost_price: number;
  retail_price: number;
  units_sold: number;
  revenue_cents: number;
  last_sold_at: string | null;
  abc_class: 'A' | 'B' | 'C' | 'DEAD';
}

interface AbcResponse {
  window_days: number;
  total_revenue_cents: number;
  items: AbcItem[];
  summary: { A: number; B: number; C: number; DEAD: number };
  clearance_suggestions: Array<{
    id: number;
    name: string;
    in_stock: number;
    tied_up_cost_cents: number;
    suggestion: string;
  }>;
}

const CLASS_COLORS: Record<string, string> = {
  A: 'bg-green-100 text-green-700 border-green-300',
  B: 'bg-blue-100 text-blue-700 border-blue-300',
  C: 'bg-amber-100 text-amber-700 border-amber-300',
  DEAD: 'bg-red-100 text-red-700 border-red-300',
};

export function AbcAnalysisPage() {
  const queryClient = useQueryClient();
  const [days, setDays] = useState(180);
  const [filter, setFilter] = useState<string>('');
  const [selectedClearance, setSelectedClearance] = useState<Set<number>>(new Set());

  const { data } = useQuery({
    queryKey: ['abc-analysis', days],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: AbcResponse }>(
        `/inventory-enrich/abc-analysis?days=${days}`,
      );
      return res.data.data;
    },
  });

  const items = data?.items || [];
  const filtered = filter ? items.filter((i) => i.abc_class === filter) : items;

  // WEB-W3-025: CSV export
  const handleExportCsv = () => {
    if (!data) return;
    const headers = ['id', 'sku', 'name', 'abc_class', 'units_sold', 'revenue', 'in_stock', 'last_sold_at'];
    const CSV_BOM = '﻿';
    const escCsv = (v: unknown) => {
      const s = v == null ? '' : String(v);
      const san = s.replace(/^[=+\-@\t\r]/, "'$&");
      return san.includes(',') || san.includes('"') || san.includes('\n')
        ? '"' + san.replace(/"/g, '""') + '"'
        : san;
    };
    const rows = filtered.map((i) => [
      i.id, i.sku ?? '', i.name, i.abc_class, i.units_sold,
      (i.revenue_cents / 100).toFixed(2), i.in_stock, i.last_sold_at ?? '',
    ].map(escCsv).join(','));
    const csv = CSV_BOM + [headers.join(','), ...rows].join('\r\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `abc-analysis-${days}d-${new Date().toISOString().slice(0, 10)}.csv`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  // WEB-W3-025: Mark for clearance mutation
  const clearanceMut = useMutation({
    mutationFn: () => inventoryApi.markClearance(Array.from(selectedClearance)),
    onSuccess: (res) => {
      const d = res.data?.data;
      toast.success(d?.message || 'Marked for clearance');
      setSelectedClearance(new Set());
      queryClient.invalidateQueries({ queryKey: ['abc-analysis', days] });
    },
    onError: () => toast.error('Failed to mark clearance'),
  });

  return (
    <div className="space-y-6">
      <div>
        <Link to="/inventory" className="text-sm text-primary-600 hover:underline inline-flex items-center gap-1">
          <ChevronLeft className="h-4 w-4" /> Back to Inventory
        </Link>
        <h1 className="text-2xl font-bold mt-2 flex items-center gap-2">
          <TrendingUp className="h-6 w-6" /> ABC Analysis
        </h1>
        <p className="text-sm text-surface-500">
          Top sellers vs dead stock — window: last {days} days
        </p>
      </div>

      <div className="flex items-center gap-3 flex-wrap">
        <select
          value={days}
          onChange={(e) => setDays(parseInt(e.target.value, 10))}
          className="rounded-md border border-surface-300 px-3 py-2 text-sm"
        >
          <option value={30}>Last 30 days</option>
          <option value={90}>Last 90 days</option>
          <option value={180}>Last 180 days</option>
          <option value={365}>Last year</option>
        </select>
        {data && (
          <button
            onClick={handleExportCsv}
            className="inline-flex items-center gap-1.5 rounded-md border border-surface-300 px-3 py-2 text-sm font-medium hover:bg-surface-50"
          >
            <Download className="h-4 w-4" /> Export CSV
          </button>
        )}
        {selectedClearance.size > 0 && (
          <button
            onClick={() => clearanceMut.mutate()}
            disabled={clearanceMut.isPending}
            className="inline-flex items-center gap-1.5 rounded-md bg-red-600 px-3 py-2 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-50"
          >
            {clearanceMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Tag className="h-4 w-4" />}
            Mark {selectedClearance.size} for Clearance (50% off)
          </button>
        )}
      </div>

      {data && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          {(['A', 'B', 'C', 'DEAD'] as const).map((cls) => (
            <button
              key={cls}
              onClick={() => setFilter(filter === cls ? '' : cls)}
              className={cn(
                'rounded-lg border-2 p-4 text-left transition-all',
                CLASS_COLORS[cls],
                filter === cls && 'ring-2 ring-offset-2 ring-primary-500',
              )}
            >
              <div className="flex items-center justify-between">
                <span className="text-lg font-bold">Class {cls}</span>
                {cls === 'DEAD' && <Skull className="h-5 w-5" />}
              </div>
              <div className="text-2xl font-bold mt-1">{data.summary[cls]}</div>
              <div className="text-xs opacity-75 mt-1">
                {cls === 'A' && 'Top 80% of revenue'}
                {cls === 'B' && 'Next 15% of revenue'}
                {cls === 'C' && 'Remaining 5%'}
                {cls === 'DEAD' && 'No sales in window'}
              </div>
            </button>
          ))}
        </div>
      )}

      {data && data.clearance_suggestions.length > 0 && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4">
          <div className="flex items-center justify-between mb-2">
            <h3 className="font-semibold text-red-800">Clearance suggestions</h3>
            <div className="flex items-center gap-2">
              <button
                onClick={() => {
                  const allIds = new Set(data.clearance_suggestions.map((s) => s.id));
                  setSelectedClearance(selectedClearance.size === allIds.size ? new Set() : allIds);
                }}
                className="text-xs text-red-700 underline"
              >
                {selectedClearance.size === data.clearance_suggestions.length ? 'Deselect all' : 'Select all'}
              </button>
            </div>
          </div>
          <p className="text-sm text-red-700 mb-3">
            {data.clearance_suggestions.length} dead-stock items tying up capital — select and mark for 50% clearance
          </p>
          <div className="space-y-1 max-h-48 overflow-y-auto">
            {data.clearance_suggestions.slice(0, 20).map((s) => (
              <div key={s.id} className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={selectedClearance.has(s.id)}
                  onChange={() => {
                    const next = new Set(selectedClearance);
                    if (next.has(s.id)) next.delete(s.id); else next.add(s.id);
                    setSelectedClearance(next);
                  }}
                  className="h-4 w-4 rounded border-red-400"
                />
                <span className="flex-1">{s.name}</span>
                <span className="font-mono text-xs">
                  {s.in_stock} units · {formatCurrency(s.tied_up_cost_cents / 100)} tied up
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="rounded-lg border border-surface-200 bg-white overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-surface-50 border-b border-surface-200">
            <tr>
              <th className="text-left px-3 py-2">Item</th>
              <th className="text-center px-3 py-2">Class</th>
              <th className="text-right px-3 py-2">Units Sold</th>
              <th className="text-right px-3 py-2">Revenue</th>
              <th className="text-right px-3 py-2">In Stock</th>
              <th className="text-left px-3 py-2">Last Sold</th>
            </tr>
          </thead>
          <tbody>
            {filtered.slice(0, 200).map((i) => (
              <tr key={i.id} className="border-b border-surface-100 last:border-0">
                <td className="px-3 py-2">
                  <div className="font-medium">{i.name}</div>
                  <div className="text-xs text-surface-500">{i.sku}</div>
                </td>
                <td className="text-center px-3 py-2">
                  <span
                    className={cn(
                      'px-2 py-0.5 rounded-full text-xs font-bold border',
                      CLASS_COLORS[i.abc_class],
                    )}
                  >
                    {i.abc_class}
                  </span>
                </td>
                <td className="text-right px-3 py-2">{i.units_sold}</td>
                <td className="text-right px-3 py-2 font-mono">
                  {formatCurrency(i.revenue_cents / 100)}
                </td>
                <td className="text-right px-3 py-2">{i.in_stock}</td>
                <td className="px-3 py-2 text-xs text-surface-500">
                  {i.last_sold_at ? new Date(i.last_sold_at).toLocaleDateString() : 'Never'}
                </td>
              </tr>
            ))}
            {filtered.length === 0 && (
              <tr>
                <td colSpan={6} className="text-center py-8 text-surface-400">
                  No items in the selected class
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
