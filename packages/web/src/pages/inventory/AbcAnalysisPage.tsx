/**
 * ABC analysis — top sellers vs dead stock with clearance suggestions.
 *
 * Cross-ref: criticalaudit.md §48 idea #7.
 */
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { ChevronLeft, TrendingUp, Skull } from 'lucide-react';
import { api } from '@/api/client';
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
  const [days, setDays] = useState(180);
  const [filter, setFilter] = useState<string>('');

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

      <div className="flex items-center gap-3">
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
          <h3 className="font-semibold text-red-800 mb-2">Clearance suggestions</h3>
          <p className="text-sm text-red-700 mb-3">
            {data.clearance_suggestions.length} dead-stock items tying up capital
          </p>
          <div className="space-y-1 max-h-48 overflow-y-auto">
            {data.clearance_suggestions.slice(0, 20).map((s) => (
              <div key={s.id} className="flex items-center justify-between text-sm">
                <span>{s.name}</span>
                <span className="font-mono">
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
