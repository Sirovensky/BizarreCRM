import { useQuery } from '@tanstack/react-query';
import { BarChart3 } from 'lucide-react';
import { api } from '@/api/client';
import { cn } from '@/utils/cn';

/**
 * Template analytics card — audit §51.11.
 *
 * Displays top templates by send count with their reply rate. Pulls from
 * GET /inbox/template-analytics which aggregates sms_template_analytics
 * counter rows (incremented when a template is sent and when an inbound
 * reply lands within 24h of a template send).
 */

interface TemplateAnalyticsCardProps {
  className?: string;
}

interface AnalyticsRow {
  template_id: number;
  name: string;
  sent_count: number;
  reply_count: number;
  reply_rate: number;
  last_sent_at: string | null;
}

async function fetchAnalytics(): Promise<AnalyticsRow[]> {
  const res = await api.get<{ success: boolean; data: AnalyticsRow[] }>(
    '/inbox/template-analytics',
  );
  return res.data.data || [];
}

function formatPct(ratio: number): string {
  if (!ratio || ratio <= 0) return '—';
  return `${Math.round(ratio * 100)}%`;
}

export function TemplateAnalyticsCard({ className }: TemplateAnalyticsCardProps) {
  const { data, isLoading } = useQuery({
    queryKey: ['template-analytics'],
    queryFn: fetchAnalytics,
    refetchInterval: 60000,
  });

  const rows = (data ?? []).slice(0, 5);

  return (
    <div
      className={cn(
        'rounded-lg border border-surface-200 bg-white p-3 dark:border-surface-700 dark:bg-surface-800',
        className,
      )}
    >
      <div className="mb-2 flex items-center gap-1.5 text-xs font-semibold text-surface-700 dark:text-surface-300">
        <BarChart3 className="h-3.5 w-3.5 text-primary-500" />
        Template Analytics
      </div>
      {isLoading ? (
        <div className="text-[11px] text-surface-400">Loading…</div>
      ) : rows.length === 0 ? (
        <div className="text-[11px] text-surface-400">
          No template sends recorded yet.
        </div>
      ) : (
        <table className="w-full text-[11px]">
          <thead>
            <tr className="text-left text-[10px] text-surface-400">
              <th className="pb-1 font-normal">Name</th>
              <th className="pb-1 text-right font-normal">Sent</th>
              <th className="pb-1 text-right font-normal">Reply</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr
                key={r.template_id}
                className="border-t border-surface-100 dark:border-surface-700"
              >
                <td className="py-1 pr-1">
                  <div className="truncate font-medium text-surface-800 dark:text-surface-200">
                    {r.name}
                  </div>
                </td>
                <td className="py-1 text-right font-mono text-surface-600 dark:text-surface-400">
                  {r.sent_count.toLocaleString()}
                </td>
                <td
                  className={cn(
                    'py-1 text-right font-mono',
                    r.reply_rate >= 0.15
                      ? 'text-green-600 dark:text-green-400'
                      : r.reply_rate >= 0.05
                      ? 'text-amber-600 dark:text-amber-400'
                      : 'text-surface-500',
                  )}
                >
                  {formatPct(r.reply_rate)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
