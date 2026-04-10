import { useQuery } from '@tanstack/react-query';
import { Cpu, Hash, DollarSign } from 'lucide-react';
import { reportApi } from '@/api/endpoints';
import { formatCurrency } from '@/utils/format';
import { LoadingState, ErrorState, EmptyState, SummaryCard } from './ReportHelpers';

interface PartsUsageData {
  rows: {
    part_name: string;
    sku: string;
    usage_count: number;
    total_qty_used: number;
    total_cost: number;
    supplier: string;
  }[];
  from: string;
  to: string;
}

export function PartsUsageTab({ from, to }: { from: string; to: string }) {
  const { data, isLoading, isError } = useQuery({
    queryKey: ['reports', 'parts-usage', from, to],
    queryFn: async () => {
      const res = await reportApi.partsUsage({ from_date: from, to_date: to });
      return res.data.data as PartsUsageData;
    },
  });

  if (isLoading) return <LoadingState />;
  if (isError || !data) return <ErrorState message="Failed to load parts usage report" />;

  const { rows } = data;
  const totalQtyUsed = rows.reduce((sum, r) => sum + r.total_qty_used, 0);
  const totalCost = rows.reduce((sum, r) => sum + r.total_cost, 0);

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <SummaryCard
          label="Unique Parts Used" value={String(rows.length)}
          icon={Cpu} color="text-cyan-500" bg="bg-cyan-50 dark:bg-cyan-950"
        />
        <SummaryCard
          label="Total Qty Used" value={String(totalQtyUsed)}
          icon={Hash} color="text-blue-500" bg="bg-blue-50 dark:bg-blue-950"
        />
        <SummaryCard
          label="Total Parts Cost" value={formatCurrency(totalCost)}
          icon={DollarSign} color="text-amber-500" bg="bg-amber-50 dark:bg-amber-950"
        />
      </div>

      {/* Top Parts Table */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Top 20 Parts Used</h3>
          <p className="text-xs text-surface-500 mt-0.5">Parts most frequently used in repairs, with supplier and cost data</p>
        </div>
        {rows.length === 0 ? (
          <EmptyState message="No parts usage data for this period" />
        ) : (
          <div className="overflow-x-auto max-h-[500px] overflow-y-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-white dark:bg-surface-900">
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">#</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Part Name</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500">SKU</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Supplier</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Times Used</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Qty Used</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Total Cost</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr key={`${r.sku}-${i}`} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                    <td className="px-4 py-3 text-surface-400 font-mono text-xs">{i + 1}</td>
                    <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">{r.part_name}</td>
                    <td className="px-4 py-3 text-surface-500 font-mono text-xs">{r.sku || '--'}</td>
                    <td className="px-4 py-3 text-surface-600 dark:text-surface-400">{r.supplier}</td>
                    <td className="px-4 py-3 text-right font-bold text-cyan-600 dark:text-cyan-400">{r.usage_count}</td>
                    <td className="px-4 py-3 text-right text-surface-900 dark:text-surface-100">{r.total_qty_used}</td>
                    <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{formatCurrency(r.total_cost)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
