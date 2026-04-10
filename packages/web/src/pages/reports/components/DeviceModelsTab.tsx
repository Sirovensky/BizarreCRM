import { useQuery } from '@tanstack/react-query';
import { Smartphone, Hash, DollarSign, Wrench } from 'lucide-react';
import { reportApi } from '@/api/endpoints';
import { formatCurrency } from '@/utils/format';
import { LoadingState, ErrorState, EmptyState, SummaryCard } from './ReportHelpers';

interface DeviceModelsData {
  rows: { model: string; repair_count: number; avg_ticket_total: number; total_parts_cost: number }[];
  from: string;
  to: string;
}

export function DeviceModelsTab({ from, to }: { from: string; to: string }) {
  const { data, isLoading, isError } = useQuery({
    queryKey: ['reports', 'device-models', from, to],
    queryFn: async () => {
      const res = await reportApi.deviceModels({ from_date: from, to_date: to });
      return res.data.data as DeviceModelsData;
    },
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message="Failed to load device model report" />;

  const { rows } = data;
  const totalRepairs = rows.reduce((sum, r) => sum + r.repair_count, 0);
  const totalPartsCost = rows.reduce((sum, r) => sum + r.total_parts_cost, 0);

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <SummaryCard
          label="Total Repairs" value={String(totalRepairs)}
          icon={Wrench} color="text-blue-500" bg="bg-blue-50 dark:bg-blue-950"
        />
        <SummaryCard
          label="Unique Models" value={String(rows.length)}
          icon={Smartphone} color="text-purple-500" bg="bg-purple-50 dark:bg-purple-950"
        />
        <SummaryCard
          label="Total Parts Cost" value={formatCurrency(totalPartsCost)}
          icon={DollarSign} color="text-amber-500" bg="bg-amber-50 dark:bg-amber-950"
        />
      </div>

      {/* Device Model Breakdown */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Repairs by Device Model</h3>
          <p className="text-xs text-surface-500 mt-0.5">Breakdown of repairs, average ticket value, and parts cost by device</p>
        </div>
        {rows.length === 0 ? (
          <EmptyState message="No device repair data for this period" />
        ) : (
          <div className="overflow-x-auto max-h-[500px] overflow-y-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-white dark:bg-surface-900">
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Model</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Repairs</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Avg Ticket</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Parts Cost</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Margin</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500 w-1/5">Volume</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => {
                  const maxRepairs = Math.max(...rows.map((x) => x.repair_count), 1);
                  const pct = (r.repair_count / maxRepairs) * 100;
                  const avgPartsCostPerRepair = r.repair_count > 0 ? r.total_parts_cost / r.repair_count : 0;
                  const margin = r.avg_ticket_total > 0
                    ? ((r.avg_ticket_total - avgPartsCostPerRepair) / r.avg_ticket_total * 100)
                    : 0;
                  return (
                    <tr key={r.model} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                      <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">{r.model}</td>
                      <td className="px-4 py-3 text-right font-bold text-blue-600 dark:text-blue-400">{r.repair_count}</td>
                      <td className="px-4 py-3 text-right text-surface-900 dark:text-surface-100">{formatCurrency(r.avg_ticket_total)}</td>
                      <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{formatCurrency(r.total_parts_cost)}</td>
                      <td className="px-4 py-3 text-right">
                        <span className={margin >= 50 ? 'text-green-600 dark:text-green-400' : margin >= 25 ? 'text-amber-600 dark:text-amber-400' : 'text-red-600 dark:text-red-400'}>
                          {margin.toFixed(0)}%
                        </span>
                      </td>
                      <td className="px-4 py-3">
                        <div className="h-4 bg-surface-100 dark:bg-surface-800 rounded-full overflow-hidden">
                          <div
                            className="h-full bg-blue-500 rounded-full transition-all"
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
    </div>
  );
}
