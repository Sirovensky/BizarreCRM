/**
 * RepeatCustomersCard — "these 10 customers = 30% of revenue" (audit 47.5)
 */

import { useQuery } from '@tanstack/react-query';
import { Users } from 'lucide-react';
import { reportApi } from '@/api/endpoints';
import { formatCurrency } from '@/utils/format';

interface RepeatCustomer {
  customer_id: number;
  name: string;
  ticket_count: number;
  total_spent: number;
  share_pct: number;
}

interface RepeatCustomersData {
  top: RepeatCustomer[];
  combined_share_pct: number;
  total_revenue: number;
}

export function RepeatCustomersCard({ limit = 10 }: { limit?: number }) {
  const { data, isLoading, error } = useQuery({
    queryKey: ['reports', 'repeat-customers', limit],
    queryFn: async () => {
      const res = await reportApi.repeatCustomers(limit);
      return res.data.data as RepeatCustomersData;
    },
  });

  return (
    <div className="rounded-xl border border-gray-200 bg-white p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="flex items-center gap-2 text-sm font-semibold text-gray-700">
          <Users size={16} className="text-indigo-500" /> Top {limit} Repeat Customers
        </div>
        {data && (
          <div className="text-xs font-semibold text-indigo-600">
            {data.combined_share_pct.toFixed(1)}% of revenue
          </div>
        )}
      </div>

      {isLoading && <div className="h-40 bg-gray-50 rounded animate-pulse" />}
      {error && <div className="text-sm text-red-600">Failed to load</div>}

      {data && (
        <ol className="space-y-1">
          {data.top.length === 0 && (
            <li className="text-sm text-gray-500 py-4">No repeat customers found yet.</li>
          )}
          {data.top.map((c, i) => (
            <li
              key={c.customer_id}
              className="flex items-center justify-between rounded px-2 py-1.5 hover:bg-gray-50 text-sm"
            >
              <div className="flex items-center gap-2 min-w-0">
                <span className="w-5 text-gray-400 tabular-nums">{i + 1}.</span>
                <span className="truncate">{c.name}</span>
                <span className="text-xs text-gray-400 flex-shrink-0">{c.ticket_count} visits</span>
              </div>
              <div className="flex items-center gap-3 flex-shrink-0">
                <span className="tabular-nums">{formatCurrency(c.total_spent)}</span>
                <span className="text-xs text-indigo-600 w-10 text-right">{c.share_pct.toFixed(1)}%</span>
              </div>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}
