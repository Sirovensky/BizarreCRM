import { useQuery } from '@tanstack/react-query';
import { UserPlus, Hash, TrendingUp } from 'lucide-react';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell,
} from 'recharts';
import { reportApi } from '@/api/endpoints';
import { LoadingState, ErrorState, EmptyState, SummaryCard } from './ReportHelpers';

const CHART_COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899', '#06b6d4', '#f97316'];

interface CustomerAcquisitionData {
  rows: { month: string; new_customers: number; acquisition_source: string }[];
  monthly_totals: { month: string; new_customers: number }[];
  from: string;
  to: string;
}

export function CustomerAcquisitionTab({ from, to }: { from: string; to: string }) {
  const { data, isLoading, isError } = useQuery({
    queryKey: ['reports', 'customer-acquisition', from, to],
    queryFn: async () => {
      const res = await reportApi.customerAcquisition({ from_date: from, to_date: to });
      return res.data.data as CustomerAcquisitionData;
    },
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message="Failed to load customer acquisition report" />;

  const { rows, monthly_totals } = data;
  const totalNew = monthly_totals.reduce((sum, r) => sum + r.new_customers, 0);

  // Aggregate by source for the source breakdown table
  const sourceMap = new Map<string, number>();
  for (const r of rows) {
    sourceMap.set(r.acquisition_source, (sourceMap.get(r.acquisition_source) || 0) + r.new_customers);
  }
  const bySource = Array.from(sourceMap.entries())
    .map(([source, count]) => ({ source, count }))
    .sort((a, b) => b.count - a.count);

  // Monthly chart data (sorted chronologically)
  const monthlyChart = [...monthly_totals].sort((a, b) => a.month.localeCompare(b.month));

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <SummaryCard
          label="Total New Customers" value={String(totalNew)}
          icon={UserPlus} color="text-green-500" bg="bg-green-50 dark:bg-green-950"
        />
        <SummaryCard
          label="Months Covered" value={String(monthly_totals.length)}
          icon={Hash} color="text-blue-500" bg="bg-blue-50 dark:bg-blue-950"
        />
        <SummaryCard
          label="Avg per Month" value={monthly_totals.length > 0 ? String(Math.round(totalNew / monthly_totals.length)) : '0'}
          icon={TrendingUp} color="text-purple-500" bg="bg-purple-50 dark:bg-purple-950"
        />
      </div>

      {/* New Customers by Month Chart */}
      {monthlyChart.length > 0 && (
        <div className="card">
          <div className="p-4 border-b border-surface-100 dark:border-surface-800">
            <h3 className="font-semibold text-surface-900 dark:text-surface-100">New Customers by Month</h3>
          </div>
          <div className="p-4" style={{ height: 300 }}>
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={monthlyChart} margin={{ left: 0, right: 20, top: 5, bottom: 5 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="currentColor" className="text-surface-200 dark:text-surface-700" />
                <XAxis dataKey="month" tick={{ fontSize: 11, fill: '#9ca3af' }} />
                <YAxis allowDecimals={false} tick={{ fontSize: 12, fill: '#9ca3af' }} />
                <Tooltip
                  contentStyle={{ backgroundColor: 'var(--color-surface-800, #1f2937)', border: '1px solid #374151', borderRadius: 8, color: '#f3f4f6' }}
                  formatter={(value: number) => [value, 'New Customers']}
                />
                <Bar dataKey="new_customers" radius={[4, 4, 0, 0]}>
                  {monthlyChart.map((_, i) => (
                    <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      )}

      {/* Source Breakdown */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Acquisition Source Breakdown</h3>
          <p className="text-xs text-surface-500 mt-0.5">Where new customers came from</p>
        </div>
        {bySource.length === 0 ? (
          <EmptyState message="No acquisition data for this period" />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Source</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Customers</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">% of Total</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500 w-1/3">Share</th>
                </tr>
              </thead>
              <tbody>
                {bySource.map((s) => {
                  const pct = totalNew > 0 ? (s.count / totalNew) * 100 : 0;
                  return (
                    <tr key={s.source} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                      <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">{s.source}</td>
                      <td className="px-4 py-3 text-right font-bold text-green-600 dark:text-green-400">{s.count}</td>
                      <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{pct.toFixed(1)}%</td>
                      <td className="px-4 py-3">
                        <div className="h-4 bg-surface-100 dark:bg-surface-800 rounded-full overflow-hidden">
                          <div
                            className="h-full bg-green-500 rounded-full transition-all"
                            style={{ width: `${pct}%` }}
                          />
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Monthly x Source Detail Table */}
      {rows.length > 0 && (
        <div className="card">
          <div className="p-4 border-b border-surface-100 dark:border-surface-800">
            <h3 className="font-semibold text-surface-900 dark:text-surface-100">Monthly Breakdown by Source</h3>
          </div>
          <div className="overflow-x-auto max-h-[400px] overflow-y-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-white dark:bg-surface-900">
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Month</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Source</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">New Customers</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr key={`${r.month}-${r.acquisition_source}-${i}`} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                    <td className="px-4 py-3 text-surface-900 dark:text-surface-100">{r.month}</td>
                    <td className="px-4 py-3 text-surface-600 dark:text-surface-400">{r.acquisition_source}</td>
                    <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">{r.new_customers}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
