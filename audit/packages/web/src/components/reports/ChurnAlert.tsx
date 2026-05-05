/**
 * ChurnAlert — customers not seen in 90+ days (audit 47.11)
 * Shows high-value at-risk customers for win-back campaigns.
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { AlertTriangle } from 'lucide-react';
import { reportApi } from '@/api/endpoints';
import { formatCurrency } from '@/utils/format';

interface ChurnCustomer {
  customer_id: number;
  name: string;
  phone: string | null;
  last_visit: string | null;
  lifetime_spent: number;
  days_inactive: number;
}

interface ChurnData {
  threshold_days: number;
  at_risk_count: number;
  customers: ChurnCustomer[];
}

export function ChurnAlert() {
  const [daysInactive, setDaysInactive] = useState(90);

  const { data, isLoading, error } = useQuery({
    queryKey: ['reports', 'churn', daysInactive],
    queryFn: async () => {
      const res = await reportApi.churn(daysInactive);
      return res.data.data as ChurnData;
    },
  });

  return (
    <div className="rounded-xl border border-gray-200 dark:border-surface-700 bg-white dark:bg-surface-900 p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="flex items-center gap-2 text-sm font-semibold text-gray-700 dark:text-surface-200">
          <AlertTriangle size={16} className="text-yellow-500" />
          At-Risk Customers
        </div>
        <select
          value={daysInactive}
          onChange={e => setDaysInactive(Number(e.target.value))}
          className="text-xs border rounded px-2 py-0.5 border-gray-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-gray-700 dark:text-surface-200"
        >
          <option value={60}>60+ days</option>
          <option value={90}>90+ days</option>
          <option value={180}>6+ months</option>
          <option value={365}>1+ year</option>
        </select>
      </div>

      {isLoading && <div className="h-32 bg-gray-50 dark:bg-surface-800 rounded animate-pulse" />}
      {error && <div className="text-sm text-red-600 dark:text-red-400">Failed to load</div>}

      {data && (
        <>
          <div className="text-3xl font-bold text-gray-900 dark:text-surface-100 tabular-nums">{data.at_risk_count}</div>
          <div className="text-xs text-gray-500 dark:text-surface-400 mb-3">
            customers not seen in {data.threshold_days}+ days
          </div>

          <ul className="space-y-1 max-h-48 overflow-y-auto text-sm">
            {data.customers.slice(0, 10).map(c => (
              <li
                key={c.customer_id}
                className="flex justify-between gap-2 px-2 py-1 rounded hover:bg-gray-50 dark:hover:bg-surface-800 text-gray-800 dark:text-surface-200"
              >
                <span className="truncate">{c.name}</span>
                <span className="flex-shrink-0 text-xs text-gray-500 dark:text-surface-400">
                  {c.days_inactive}d · {formatCurrency(c.lifetime_spent)}
                </span>
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}
