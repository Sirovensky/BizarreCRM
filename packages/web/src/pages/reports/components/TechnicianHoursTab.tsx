import { useQuery } from '@tanstack/react-query';
import { Clock, DollarSign, Ticket } from 'lucide-react';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell,
} from 'recharts';
import { reportApi } from '@/api/endpoints';
import { formatCurrency } from '@/utils/format';
import { LoadingState, ErrorState, EmptyState, SummaryCard } from './ReportHelpers';

const CHART_COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899', '#06b6d4', '#f97316'];

interface TechnicianHoursData {
  rows: {
    tech_name: string;
    tickets_closed: number;
    total_revenue: number;
    hours_logged: number;
  }[];
  from: string;
  to: string;
}

export function TechnicianHoursTab({ from, to }: { from: string; to: string }) {
  const { data, isLoading, isError } = useQuery({
    queryKey: ['reports', 'technician-hours', from, to],
    queryFn: async () => {
      const res = await reportApi.technicianHours({ from_date: from, to_date: to });
      return res.data.data as TechnicianHoursData;
    },
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message="Failed to load technician hours report" />;

  const { rows } = data;
  const totalHours = rows.reduce((sum, r) => sum + r.hours_logged, 0);
  const totalRevenue = rows.reduce((sum, r) => sum + r.total_revenue, 0);
  const totalClosed = rows.reduce((sum, r) => sum + r.tickets_closed, 0);

  const chartData = rows.map((r) => ({
    name: r.tech_name.split(' ')[0],
    hours: Number(r.hours_logged.toFixed(1)),
    revenue: r.total_revenue,
    revenuePerHour: r.hours_logged > 0 ? Number((r.total_revenue / r.hours_logged).toFixed(2)) : 0,
  }));

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <SummaryCard
          label="Total Hours Logged" value={`${totalHours.toFixed(1)}h`}
          icon={Clock} color="text-blue-500" bg="bg-blue-50 dark:bg-blue-950"
        />
        <SummaryCard
          label="Total Revenue" value={formatCurrency(totalRevenue)}
          icon={DollarSign} color="text-green-500" bg="bg-green-50 dark:bg-green-950"
        />
        <SummaryCard
          label="Tickets Closed" value={String(totalClosed)}
          icon={Ticket} color="text-purple-500" bg="bg-purple-50 dark:bg-purple-950"
        />
      </div>

      {/* Revenue per Hour Chart */}
      {chartData.length > 0 && (
        <div className="card">
          <div className="p-4 border-b border-surface-100 dark:border-surface-800">
            <h3 className="font-semibold text-surface-900 dark:text-surface-100">Revenue per Hour by Technician</h3>
            <p className="text-xs text-surface-500 mt-0.5">Hours logged vs revenue generated comparison</p>
          </div>
          <div className="p-4" style={{ height: 300 }}>
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={chartData} barCategoryGap="20%">
                <CartesianGrid strokeDasharray="3 3" stroke="currentColor" className="text-surface-200 dark:text-surface-700" />
                <XAxis dataKey="name" tick={{ fontSize: 12, fill: '#9ca3af' }} />
                <YAxis yAxisId="hours" orientation="left" tick={{ fontSize: 12, fill: '#9ca3af' }} label={{ value: 'Hours', angle: -90, position: 'insideLeft', fontSize: 11, fill: '#9ca3af' }} />
                {/* @audit-fixed (WEB-FF-003 / Fixer-UUU 2026-04-25): hardcoded "$" → formatCurrency for tenant currency */}
                <YAxis yAxisId="revenue" orientation="right" tick={{ fontSize: 12, fill: '#9ca3af' }} tickFormatter={(v: number) => formatCurrency(v)} label={{ value: 'Revenue', angle: 90, position: 'insideRight', fontSize: 11, fill: '#9ca3af' }} />
                <Tooltip
                  contentStyle={{ backgroundColor: 'var(--color-surface-800, #1f2937)', border: '1px solid #374151', borderRadius: 8, color: '#f3f4f6' }}
                  formatter={(value: number, name: string) => {
                    if (name === 'hours') return [`${value}h`, 'Hours Logged'];
                    return [formatCurrency(value), 'Revenue'];
                  }}
                />
                <Bar yAxisId="hours" dataKey="hours" fill="#3b82f6" radius={[4, 4, 0, 0]} name="hours">
                  {chartData.map((_, i) => (
                    <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} opacity={0.6} />
                  ))}
                </Bar>
                <Bar yAxisId="revenue" dataKey="revenue" fill="#10b981" radius={[4, 4, 0, 0]} name="revenue">
                  {chartData.map((_, i) => (
                    <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      )}

      {/* Detailed Table */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Technician Details</h3>
        </div>
        {rows.length === 0 ? (
          <EmptyState message="No technician data for this period" />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Technician</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Tickets Closed</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Hours Logged</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Revenue</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">$/Hour</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => {
                  const revenuePerHour = r.hours_logged > 0 ? r.total_revenue / r.hours_logged : 0;
                  return (
                    <tr key={r.tech_name} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                      <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">{r.tech_name}</td>
                      <td className="px-4 py-3 text-right text-green-600 dark:text-green-400">{r.tickets_closed}</td>
                      <td className="px-4 py-3 text-right text-surface-900 dark:text-surface-100">{r.hours_logged.toFixed(1)}h</td>
                      <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{formatCurrency(r.total_revenue)}</td>
                      <td className="px-4 py-3 text-right font-bold">
                        <span className={revenuePerHour >= 100 ? 'text-green-600 dark:text-green-400' : revenuePerHour >= 50 ? 'text-amber-600 dark:text-amber-400' : 'text-red-600 dark:text-red-400'}>
                          {formatCurrency(revenuePerHour)}
                        </span>
                      </td>
                    </tr>
                  );
                })}
                {/* Totals row */}
                <tr className="bg-surface-50 dark:bg-surface-800/30 font-semibold">
                  <td className="px-4 py-3 text-surface-900 dark:text-surface-100">Total</td>
                  <td className="px-4 py-3 text-right text-surface-900 dark:text-surface-100">{totalClosed}</td>
                  <td className="px-4 py-3 text-right text-surface-900 dark:text-surface-100">{totalHours.toFixed(1)}h</td>
                  <td className="px-4 py-3 text-right text-surface-900 dark:text-surface-100">{formatCurrency(totalRevenue)}</td>
                  <td className="px-4 py-3 text-right text-surface-900 dark:text-surface-100">
                    {totalHours > 0 ? formatCurrency(totalRevenue / totalHours) : '--'}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
