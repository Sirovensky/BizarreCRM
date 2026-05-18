/**
 * Inventory age report — 0-3 / 3-12 / 12+ month buckets with cost tied up.
 *
 * Cross-ref: criticalaudit.md §48 idea #9.
 */
import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { ChevronLeft, Clock, Loader2 } from 'lucide-react';
import { api } from '@/api/client';
import { cn } from '@/utils/cn';
import { formatCurrency } from '@/utils/format';

interface AgeItem {
  id: number;
  name: string;
  sku: string | null;
  in_stock: number;
  cost_price: number;
  first_received: string;
  age_days: number;
}

interface AgeResponse {
  buckets: {
    fresh_0_3_months: AgeItem[];
    aging_3_12_months: AgeItem[];
    stale_12_plus: AgeItem[];
  };
  summary: {
    fresh_count: number;
    aging_count: number;
    stale_count: number;
    fresh_0_3_months_cost_cents: number;
    aging_3_12_months_cost_cents: number;
    stale_12_plus_cost_cents: number;
  };
}

export function InventoryAgePage() {
  const { data, isLoading } = useQuery({
    queryKey: ['inventory-age'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: AgeResponse }>(
        '/inventory-enrich/age-report',
      );
      return res.data.data;
    },
  });

  const renderBucket = (
    title: string,
    items: AgeItem[],
    totalCostCents: number,
    color: string,
  ) => (
    <div className="rounded-lg border border-surface-200 bg-white overflow-hidden dark:border-surface-700 dark:bg-surface-800">
      <div className={cn('px-4 py-3 border-b dark:border-surface-700', color)}>
        <div className="flex items-center justify-between">
          <h3 className="font-semibold">{title}</h3>
          <div className="text-sm">
            {items.length} items · {formatCurrency(totalCostCents / 100)} tied up
          </div>
        </div>
      </div>
      <div className="max-h-80 overflow-y-auto overflow-x-auto">
        <table className="w-full text-sm" aria-label="Inventory items sorted by age with stock and unit cost">
          <thead className="bg-surface-50 border-b border-surface-200 sticky top-0 dark:border-surface-700 dark:bg-surface-900">
            <tr>
              <th scope="col" className="text-left px-3 py-2">Item</th>
              <th scope="col" className="text-right px-3 py-2">Stock</th>
              <th scope="col" className="text-right px-3 py-2">Cost/Unit</th>
              <th scope="col" className="text-right px-3 py-2">Age</th>
            </tr>
          </thead>
          <tbody>
            {items.length === 0 && (
              <tr>
                <td colSpan={4} className="text-center py-6 text-surface-400">
                  No items in this bucket
                </td>
              </tr>
            )}
            {items.slice(0, 100).map((i) => (
              <tr key={i.id} className="border-b border-surface-100 last:border-0 dark:border-surface-700">
                <td className="px-3 py-2">
                  <div className="font-medium text-xs">{i.name}</div>
                  <div className="text-xs text-surface-500">{i.sku}</div>
                </td>
                <td className="text-right px-3 py-2">{i.in_stock}</td>
                <td className="text-right px-3 py-2">{formatCurrency(i.cost_price)}</td>
                <td className="text-right px-3 py-2 text-xs">{i.age_days}d</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );

  return (
    <div className="space-y-6">
      <div>
        <Link to="/inventory" className="text-sm text-primary-600 hover:underline inline-flex items-center gap-1">
          <ChevronLeft className="h-4 w-4" /> Back to Inventory
        </Link>
        <h1 className="text-2xl font-bold mt-2 flex items-center gap-2">
          <Clock className="h-6 w-6" /> Inventory Age Report
        </h1>
        <p className="text-sm text-surface-500">
          Bucketed by age from first received — spot slow-moving capital
        </p>
      </div>

      {isLoading && (
        <div
          role="status"
          aria-live="polite"
          className="flex items-center gap-3 rounded-lg border border-surface-200 bg-white p-6 text-sm text-surface-600 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300"
        >
          <Loader2 className="h-5 w-5 animate-spin text-surface-400" />
          <span>Loading inventory age report...</span>
        </div>
      )}

      {data && (
        <>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div className="rounded-lg border border-green-200 bg-green-50 p-4 dark:border-green-900/60 dark:bg-green-950/30">
              <div className="text-sm text-green-700 dark:text-green-300">Fresh (0-3 months)</div>
              <div className="text-2xl font-bold text-green-800 dark:text-green-100">{data.summary.fresh_count}</div>
              <div className="text-xs text-green-700 dark:text-green-300">
                {formatCurrency(data.summary.fresh_0_3_months_cost_cents / 100)}
              </div>
            </div>
            <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 dark:border-amber-900/60 dark:bg-amber-950/30">
              <div className="text-sm text-amber-700 dark:text-amber-300">Aging (3-12 months)</div>
              <div className="text-2xl font-bold text-amber-800 dark:text-amber-100">{data.summary.aging_count}</div>
              <div className="text-xs text-amber-700 dark:text-amber-300">
                {formatCurrency(data.summary.aging_3_12_months_cost_cents / 100)}
              </div>
            </div>
            <div className="rounded-lg border border-red-200 bg-red-50 p-4 dark:border-red-900/60 dark:bg-red-950/30">
              <div className="text-sm text-red-700 dark:text-red-300">Stale (12+ months)</div>
              <div className="text-2xl font-bold text-red-800 dark:text-red-100">{data.summary.stale_count}</div>
              <div className="text-xs text-red-700 dark:text-red-300">
                {formatCurrency(data.summary.stale_12_plus_cost_cents / 100)}
              </div>
            </div>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
            {renderBucket(
              'Fresh (0-3 months)',
              data.buckets.fresh_0_3_months,
              data.summary.fresh_0_3_months_cost_cents,
              'bg-green-50 text-green-800 dark:bg-green-950/40 dark:text-green-100',
            )}
            {renderBucket(
              'Aging (3-12 months)',
              data.buckets.aging_3_12_months,
              data.summary.aging_3_12_months_cost_cents,
              'bg-amber-50 text-amber-800 dark:bg-amber-950/40 dark:text-amber-100',
            )}
            {renderBucket(
              'Stale (12+ months)',
              data.buckets.stale_12_plus,
              data.summary.stale_12_plus_cost_cents,
              'bg-red-50 text-red-800 dark:bg-red-950/40 dark:text-red-100',
            )}
          </div>
        </>
      )}
    </div>
  );
}
