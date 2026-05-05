/**
 * ForecastChart — 12-month demand forecast per category (audit 47.10)
 * Simple text-forward visualization; uses arrow indicators instead of charts
 * to keep the bundle lean.
 */

import { useQuery } from '@tanstack/react-query';
import { TrendingUp, TrendingDown, Minus } from 'lucide-react';
import { reportApi } from '@/api/endpoints';

interface ForecastCategory {
  category: string;
  history: Array<{ ym: string; units: number }>;
  avg_monthly: number;
  next_month_forecast: number;
  trend_pct: number;
}

interface ForecastData {
  forecast: ForecastCategory[];
  months_analyzed: number;
}

function TrendIcon({ pct }: { pct: number }) {
  if (pct > 5) return <TrendingUp size={14} className="text-green-600 dark:text-green-400" />;
  if (pct < -5) return <TrendingDown size={14} className="text-red-600 dark:text-red-400" />;
  return <Minus size={14} className="text-gray-400 dark:text-surface-500" />;
}

export function ForecastChart() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['reports', 'demand-forecast'],
    queryFn: async () => {
      const res = await reportApi.demandForecast(12);
      return res.data.data as ForecastData;
    },
  });

  return (
    <div className="rounded-xl border border-gray-200 dark:border-surface-700 bg-white dark:bg-surface-900 p-4">
      <div className="mb-3 flex items-center gap-2 text-sm font-semibold text-gray-700 dark:text-surface-200">
        Demand Forecast &mdash; next month
      </div>

      {isLoading && <div className="h-40 bg-gray-50 dark:bg-surface-800 rounded animate-pulse" />}
      {error && <div className="text-sm text-red-600 dark:text-red-400">Failed to load</div>}

      {data && (
        <div className="overflow-x-auto">
        <table className="w-full text-sm text-gray-800 dark:text-surface-200">
          <thead>
            <tr className="text-left text-xs uppercase text-gray-500 dark:text-surface-400 border-b border-gray-200 dark:border-surface-700">
              <th className="py-2">Category</th>
              <th className="py-2 text-right">Avg/mo</th>
              <th className="py-2 text-right">Next</th>
              <th className="py-2 text-right">Trend</th>
            </tr>
          </thead>
          <tbody>
            {data.forecast.length === 0 && (
              <tr>
                <td colSpan={4} className="py-4 text-center text-gray-500 dark:text-surface-400">
                  Not enough history yet.
                </td>
              </tr>
            )}
            {data.forecast.slice(0, 10).map(f => (
              <tr key={f.category} className="border-b last:border-0 border-gray-200 dark:border-surface-700">
                <td className="py-2 truncate">{f.category}</td>
                <td className="py-2 text-right tabular-nums">{f.avg_monthly}</td>
                <td className="py-2 text-right tabular-nums font-semibold">{f.next_month_forecast}</td>
                <td className="py-2 text-right">
                  <div className="inline-flex items-center gap-1">
                    <TrendIcon pct={f.trend_pct} />
                    <span className="tabular-nums text-xs">{f.trend_pct > 0 ? '+' : ''}{f.trend_pct}%</span>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
      )}
    </div>
  );
}
