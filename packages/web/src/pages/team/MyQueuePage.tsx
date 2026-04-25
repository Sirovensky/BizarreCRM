/**
 * "My queue" tech dashboard — criticalaudit.md §53 idea #2.
 *
 * Shows tickets assigned to the logged-in user, sorted by due date, then age.
 * Each row has start/ready/complete actions that link to the existing ticket
 * detail page (the actual status mutation lives there). The endpoint
 * `GET /api/v1/team/my-queue` does the filtering server-side.
 */
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Clock, AlertCircle, CheckCircle2, ArrowRight } from 'lucide-react';
import { api } from '@/api/client';
import { formatCurrency } from '@/utils/format';

interface QueueTicket {
  id: number;
  order_id: string;
  customer_id: number;
  status_id: number;
  status_name: string | null;
  is_closed: number | null;
  assigned_to: number | null;
  due_on: string | null;
  created_at: string;
  updated_at: string;
  total: number;
  first_name: string | null;
  last_name: string | null;
}

function ageBadge(createdAt: string): { label: string; color: string } {
  const ageMs = Date.now() - new Date(createdAt).getTime();
  const days = Math.floor(ageMs / 86400000);
  if (days >= 14) return { label: `${days}d old`, color: 'bg-red-100 text-red-700' };
  if (days >= 7)  return { label: `${days}d old`, color: 'bg-amber-100 text-amber-700' };
  if (days >= 3)  return { label: `${days}d old`, color: 'bg-yellow-100 text-yellow-700' };
  return { label: `${days}d old`, color: 'bg-gray-100 text-gray-700' };
}

function dueBadge(dueOn: string | null): { label: string; color: string } | null {
  if (!dueOn) return null;
  const due = new Date(dueOn).getTime();
  const now = Date.now();
  const diffDays = Math.floor((due - now) / 86400000);
  if (diffDays < 0)  return { label: `${Math.abs(diffDays)}d overdue`, color: 'bg-red-100 text-red-700' };
  if (diffDays === 0) return { label: 'due today', color: 'bg-amber-100 text-amber-700' };
  if (diffDays <= 2)  return { label: `due in ${diffDays}d`, color: 'bg-yellow-100 text-yellow-700' };
  return { label: `due ${new Date(dueOn).toLocaleDateString()}`, color: 'bg-gray-100 text-gray-700' };
}

export function MyQueuePage() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['team', 'my-queue'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: QueueTicket[] }>('/team/my-queue');
      return res.data.data;
    },
    refetchInterval: 30_000,
  });

  const tickets: QueueTicket[] = data || [];

  return (
    <div className="p-6 max-w-6xl mx-auto">
      <header className="mb-6">
        <h1 className="text-2xl font-bold text-gray-800 dark:text-surface-100">My Queue</h1>
        <p className="text-sm text-gray-500 dark:text-surface-400">
          Tickets assigned to you, sorted by due date and age. Updates every 30 seconds.
        </p>
      </header>

      {isLoading && (
        <div className="flex items-center justify-center py-12 text-gray-500">
          <Clock className="w-5 h-5 animate-spin mr-2" /> Loading queue...
        </div>
      )}

      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 rounded p-4 flex items-center">
          <AlertCircle className="w-5 h-5 mr-2" />
          Failed to load your queue. Try refreshing.
        </div>
      )}

      {!isLoading && tickets.length === 0 && (
        <div className="bg-white dark:bg-surface-900 border dark:border-surface-700 rounded-lg p-12 text-center">
          <CheckCircle2 className="w-12 h-12 text-green-500 mx-auto mb-3" />
          <h2 className="text-lg font-semibold text-gray-800 dark:text-surface-100">All caught up</h2>
          <p className="text-sm text-gray-500 dark:text-surface-400 mt-1">
            You have no open tickets assigned to you right now.
          </p>
        </div>
      )}

      {tickets.length > 0 && (
        <div className="bg-white dark:bg-surface-900 rounded-lg shadow border dark:border-surface-700 overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 dark:bg-surface-800 text-gray-600 dark:text-surface-300 text-left text-xs uppercase">
              <tr>
                <th className="px-4 py-3">Order</th>
                <th className="px-4 py-3">Customer</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Age</th>
                <th className="px-4 py-3">Due</th>
                <th className="px-4 py-3 text-right">Total</th>
                <th className="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {tickets.map((t) => {
                const age = ageBadge(t.created_at);
                const due = dueBadge(t.due_on);
                return (
                  <tr key={t.id} className="hover:bg-gray-50 dark:hover:bg-surface-800/50">
                    <td className="px-4 py-3 font-mono text-xs text-primary-600">{t.order_id}</td>
                    <td className="px-4 py-3">
                      {t.first_name || ''} {t.last_name || ''}
                    </td>
                    <td className="px-4 py-3">
                      <span className="inline-block px-2 py-0.5 rounded-full text-xs bg-primary-50 text-primary-700">
                        {t.status_name || '—'}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <span className={`inline-block px-2 py-0.5 rounded-full text-xs ${age.color}`}>
                        {age.label}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      {due ? (
                        <span className={`inline-block px-2 py-0.5 rounded-full text-xs ${due.color}`}>
                          {due.label}
                        </span>
                      ) : (
                        <span className="text-xs text-gray-400">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right font-mono">
                      {formatCurrency(Number(t.total || 0))}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Link
                        to={`/tickets/${t.id}`}
                        className="inline-flex items-center text-primary-600 hover:text-primary-800 text-xs font-semibold"
                      >
                        Open <ArrowRight className="w-3 h-3 ml-1" />
                      </Link>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
