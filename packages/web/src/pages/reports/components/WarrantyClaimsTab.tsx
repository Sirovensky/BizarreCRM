import { useQuery } from '@tanstack/react-query';
import { ShieldAlert, DollarSign, Hash } from 'lucide-react';
import { reportApi } from '@/api/endpoints';
import { formatCurrency } from '@/utils/format';
import { LoadingState, ErrorState, EmptyState, SummaryCard } from './ReportHelpers';

interface WarrantyClaimsData {
  rows: { model: string; claim_count: number; total_cost: number; avg_repair_cost: number }[];
  from: string;
  to: string;
}

export function WarrantyClaimsTab({ from, to }: { from: string; to: string }) {
  const { data, isLoading, isError } = useQuery({
    queryKey: ['reports', 'warranty-claims', from, to],
    queryFn: async () => {
      const res = await reportApi.warrantyClaims({ from_date: from, to_date: to });
      return res.data.data as WarrantyClaimsData;
    },
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message="Failed to load warranty claims report" />;

  const { rows } = data;
  const totalClaims = rows.reduce((sum, r) => sum + r.claim_count, 0);
  const totalCost = rows.reduce((sum, r) => sum + r.total_cost, 0);

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <SummaryCard
          label="Total Claims" value={String(totalClaims)}
          icon={Hash} color="text-red-500" bg="bg-red-50 dark:bg-red-950"
        />
        <SummaryCard
          label="Total Cost" value={formatCurrency(totalCost)}
          icon={DollarSign} color="text-amber-500" bg="bg-amber-50 dark:bg-amber-950"
        />
        <SummaryCard
          label="Models Affected" value={String(rows.length)}
          icon={ShieldAlert} color="text-purple-500" bg="bg-purple-50 dark:bg-purple-950"
        />
      </div>

      {/* Warranty Claims by Model */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Warranty Claims by Device Model</h3>
          <p className="text-xs text-surface-500 mt-0.5">Devices repaired under warranty, sorted by claim count</p>
        </div>
        {rows.length === 0 ? (
          <EmptyState message="No warranty claims in this period" />
        ) : (
          <div className="overflow-x-auto max-h-[500px] overflow-y-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-white dark:bg-surface-900">
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Model</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Claims</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Total Cost</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Avg Cost</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500 w-1/4">Volume</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => {
                  const maxClaims = Math.max(...rows.map((x) => x.claim_count), 1);
                  const pct = (r.claim_count / maxClaims) * 100;
                  return (
                    <tr key={r.model} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                      <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">{r.model}</td>
                      <td className="px-4 py-3 text-right font-bold text-red-600 dark:text-red-400">{r.claim_count}</td>
                      <td className="px-4 py-3 text-right text-surface-900 dark:text-surface-100">{formatCurrency(r.total_cost)}</td>
                      <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{formatCurrency(r.avg_repair_cost)}</td>
                      <td className="px-4 py-3">
                        <div className="h-4 bg-surface-100 dark:bg-surface-800 rounded-full overflow-hidden">
                          <div
                            className="h-full bg-red-500 rounded-full transition-all"
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
