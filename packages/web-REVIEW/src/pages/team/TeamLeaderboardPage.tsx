/**
 * Team leaderboard — criticalaudit.md §53 idea #3.
 *
 * Consumes the existing `/api/v1/reports/tech-leaderboard` endpoint owned by
 * the reports agent. We do NOT re-implement the aggregation here.
 *
 * Falls back to the employee performance summary if the dedicated endpoint
 * isn't available — keeps the page useful even if the reports module hasn't
 * shipped its enrichment yet.
 */
import { useQuery } from '@tanstack/react-query';
import { Trophy, TrendingUp, Loader2 } from 'lucide-react';
import { api } from '@/api/client';
import { formatCurrency } from '@/utils/format';

interface LeaderboardRow {
  user_id?: number;
  id?: number;
  first_name: string;
  last_name: string;
  tickets_closed?: number;
  closed_tickets?: number;
  total_tickets?: number;
  revenue?: number;
  total_revenue?: number;
  avg_resolution_hours?: number;
  avg_repair_hours?: number;
  csat?: number | null;
}

async function fetchLeaderboard(): Promise<LeaderboardRow[]> {
  // Try the rich tech-leaderboard endpoint first.
  try {
    const res = await api.get<{ success: boolean; data: LeaderboardRow[] }>('/reports/tech-leaderboard');
    if (Array.isArray(res?.data?.data)) return res.data.data;
  } catch {
    /* fall through to the simpler employees performance endpoint */
  }
  const res = await api.get<{ success: boolean; data: LeaderboardRow[] }>('/employees/performance/all');
  return res.data.data;
}

function rowKey(r: LeaderboardRow): number {
  return r.user_id ?? r.id ?? Math.random();
}

function ticketsClosed(r: LeaderboardRow): number {
  return Number(r.tickets_closed ?? r.closed_tickets ?? 0);
}

function revenue(r: LeaderboardRow): number {
  return Number(r.revenue ?? r.total_revenue ?? 0);
}

export function TeamLeaderboardPage() {
  const { data, isLoading } = useQuery({
    queryKey: ['team', 'leaderboard'],
    queryFn: fetchLeaderboard,
  });
  const rows: LeaderboardRow[] = data || [];

  // Sort by tickets closed desc; tie-break on revenue.
  const sorted = [...rows].sort((a, b) => {
    const ca = ticketsClosed(a);
    const cb = ticketsClosed(b);
    if (cb !== ca) return cb - ca;
    return revenue(b) - revenue(a);
  });

  return (
    <div className="p-6 max-w-5xl mx-auto">
      <header className="mb-6">
        <h1 className="text-2xl font-bold text-gray-800 dark:text-surface-100 inline-flex items-center">
          <Trophy className="w-6 h-6 mr-2 text-amber-500" /> Team Leaderboard
        </h1>
        <p className="text-sm text-gray-500 dark:text-surface-400">
          Tickets closed and revenue by tech. Refreshes when you reload.
        </p>
      </header>

      {isLoading && (
        <div className="flex items-center justify-center py-12 text-gray-500 dark:text-surface-400">
          <Loader2 className="w-5 h-5 animate-spin mr-2" /> Loading leaderboard...
        </div>
      )}

      {!isLoading && sorted.length === 0 && (
        <div className="bg-white dark:bg-surface-900 border dark:border-surface-700 rounded-lg p-12 text-center text-gray-500 dark:text-surface-400">
          No data yet — close some tickets to populate the leaderboard.
        </div>
      )}

      {sorted.length > 0 && (
        <div className="bg-white dark:bg-surface-900 rounded-lg shadow border dark:border-surface-700 overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 dark:bg-surface-800 text-gray-600 dark:text-surface-300 text-left text-xs uppercase">
              <tr>
                <th className="px-4 py-3 w-12">#</th>
                <th className="px-4 py-3">Name</th>
                <th className="px-4 py-3 text-right">Closed</th>
                <th className="px-4 py-3 text-right">Revenue</th>
                <th className="px-4 py-3 text-right">Avg hours</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {sorted.map((r, i) => (
                <tr key={rowKey(r)} className={i < 3 ? 'bg-amber-50/40 dark:bg-amber-900/10' : ''}>
                  <td className="px-4 py-3 font-bold text-gray-500 dark:text-surface-400">
                    {i === 0 && <span className="text-2xl">🥇</span>}
                    {i === 1 && <span className="text-2xl">🥈</span>}
                    {i === 2 && <span className="text-2xl">🥉</span>}
                    {i > 2 && <span>{i + 1}</span>}
                  </td>
                  <td className="px-4 py-3 font-semibold text-gray-800 dark:text-surface-100">
                    {r.first_name} {r.last_name}
                  </td>
                  <td className="px-4 py-3 text-right font-mono">{ticketsClosed(r)}</td>
                  <td className="px-4 py-3 text-right font-mono inline-flex items-center justify-end gap-1">
                    <TrendingUp className="w-3 h-3 text-green-500" />
                    {formatCurrency(revenue(r))}
                  </td>
                  <td className="px-4 py-3 text-right font-mono">
                    {(r.avg_resolution_hours ?? r.avg_repair_hours ?? 0).toFixed(1)}h
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
