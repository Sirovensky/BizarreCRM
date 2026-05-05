/**
 * CashTrappedCard — slow-moving inventory dollar count (audit 47.8)
 */

import { useQuery } from '@tanstack/react-query';
import { PackageX } from 'lucide-react';
import { reportApi } from '@/api/endpoints';
import { formatCurrency } from '@/utils/format';

interface CashTrappedData {
  total_cash_trapped: number;
  item_count: number;
  top_offenders: Array<{
    id: number;
    name: string;
    category: string | null;
    in_stock: number;
    cost_price: number;
    value: number;
    last_sold: string | null;
  }>;
}

export function CashTrappedCard() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['reports', 'cash-trapped'],
    queryFn: async () => {
      const res = await reportApi.cashTrapped();
      return res.data.data as CashTrappedData;
    },
  });

  if (isLoading) {
    return <div className="h-48 rounded-xl border border-gray-200 dark:border-surface-700 bg-gray-50 dark:bg-surface-800 animate-pulse" />;
  }
  if (error || !data) {
    return <div className="rounded-xl border border-red-200 dark:border-red-900 bg-red-50 dark:bg-red-900/20 p-4 text-red-700 dark:text-red-300 text-sm">Unavailable.</div>;
  }

  return (
    <div className="rounded-xl border-2 border-orange-300 dark:border-orange-800 bg-orange-50 dark:bg-orange-900/20 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-orange-900 dark:text-orange-200">
        <PackageX size={16} /> Cash Trapped in Slow Stock
      </div>
      <div className="mt-2 text-3xl font-black text-orange-900 dark:text-orange-200 tabular-nums">
        {formatCurrency(data.total_cash_trapped)}
      </div>
      <div className="text-xs text-orange-700 dark:text-orange-300">
        Across {data.item_count} items unsold for 90+ days
      </div>

      {data.top_offenders.length > 0 && (
        <ul className="mt-3 space-y-1 max-h-48 overflow-y-auto text-sm">
          {data.top_offenders.slice(0, 5).map(item => (
            <li key={item.id} className="flex justify-between bg-white/50 dark:bg-surface-900/50 rounded px-2 py-1">
              <span className="truncate mr-2">{item.name}</span>
              <span className="flex-shrink-0 tabular-nums text-orange-800 dark:text-orange-300">
                {formatCurrency(item.value)}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
