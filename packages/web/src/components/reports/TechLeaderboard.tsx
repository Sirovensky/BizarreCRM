/**
 * TechLeaderboard — tickets closed, revenue, CSAT per technician (audit 47.4)
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Trophy } from 'lucide-react';
import { reportApi } from '@/api/endpoints';
import { formatCurrency } from '@/utils/format';

type Period = 'week' | 'month' | 'quarter';

interface LeaderboardRow {
  user_id: number;
  name: string;
  tickets_closed: number;
  revenue: number;
  avg_resolution_hours: number | null;
  csat_avg: number | null;
  csat_responses: number;
}

interface LeaderboardPayload {
  period: Period;
  leaderboard: LeaderboardRow[];
}

export function TechLeaderboard() {
  const [period, setPeriod] = useState<Period>('month');

  const { data, isLoading, error } = useQuery({
    queryKey: ['reports', 'tech-leaderboard', period],
    queryFn: async () => {
      const res = await reportApi.techLeaderboard(period);
      return res.data.data as LeaderboardPayload;
    },
  });

  return (
    <div className="rounded-xl border border-gray-200 bg-white p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="flex items-center gap-2 text-sm font-semibold text-gray-700">
          <Trophy size={16} className="text-amber-500" /> Technician Leaderboard
        </div>
        <div className="flex gap-1">
          {(['week', 'month', 'quarter'] as Period[]).map(p => (
            <button
              key={p}
              type="button"
              onClick={() => setPeriod(p)}
              className={`px-2 py-0.5 text-xs rounded ${
                period === p ? 'bg-gray-800 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
              }`}
            >
              {p}
            </button>
          ))}
        </div>
      </div>

      {isLoading && <div className="h-40 bg-gray-50 rounded animate-pulse" />}
      {error && <div className="text-sm text-red-600">Failed to load leaderboard</div>}

      {data && (
        <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-xs uppercase text-gray-500 border-b">
              <th className="py-2">Technician</th>
              <th className="py-2 text-right">Closed</th>
              <th className="py-2 text-right">Revenue</th>
              <th className="py-2 text-right">CSAT</th>
            </tr>
          </thead>
          <tbody>
            {data.leaderboard.length === 0 && (
              <tr>
                <td colSpan={4} className="py-6 text-center text-gray-500">
                  No closed tickets in this period yet.
                </td>
              </tr>
            )}
            {data.leaderboard.map((row, i) => (
              <tr key={row.user_id} className="border-b last:border-0">
                <td className="py-2">
                  <span className="inline-block w-6 text-gray-400">{i + 1}.</span>
                  {row.name}
                </td>
                <td className="py-2 text-right tabular-nums">{row.tickets_closed}</td>
                <td className="py-2 text-right tabular-nums">{formatCurrency(row.revenue)}</td>
                <td className="py-2 text-right tabular-nums">
                  {row.csat_avg != null ? `${row.csat_avg.toFixed(1)} / 10` : '—'}
                  {row.csat_responses > 0 && (
                    <span className="ml-1 text-xs text-gray-400">({row.csat_responses})</span>
                  )}
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
