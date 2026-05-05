import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { RotateCcw, X, AlertCircle } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { cn } from '@/utils/cn';
import { formatPhone } from '@/utils/format';

/**
 * Failed send retry list — audit §51.4.
 *
 * Surfaces rows from sms_retry_queue with status pending|failed, one row
 * per failed send. Each row has Retry / Cancel buttons. Retry increments
 * retry_count and re-schedules next_retry_at with exponential backoff
 * (server-side logic in inbox.routes nextRetryAt()).
 */

interface FailedSendRetryListProps {
  className?: string;
}

interface RetryRow {
  id: number;
  original_message_id: number | null;
  to_phone: string;
  body: string;
  retry_count: number;
  next_retry_at: string;
  last_error: string | null;
  status: 'pending' | 'failed' | 'succeeded' | 'cancelled';
  created_at: string;
}

async function fetchQueue(): Promise<RetryRow[]> {
  const res = await api.get<{ success: boolean; data: RetryRow[] }>('/inbox/retry-queue');
  return res.data.data || [];
}

function truncate(s: string, len: number) {
  return s.length > len ? s.slice(0, len) + '…' : s;
}

export function FailedSendRetryList({ className }: FailedSendRetryListProps) {
  const qc = useQueryClient();

  const { data: rows = [], isLoading } = useQuery({
    queryKey: ['inbox-retry-queue'],
    queryFn: fetchQueue,
    refetchInterval: 30000,
  });

  const retryMut = useMutation({
    mutationFn: (id: number) => api.post(`/inbox/retry-queue/${id}/retry`),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['inbox-retry-queue'] });
      toast.success('Retry scheduled');
    },
    onError: (e: any) => toast.error(e?.response?.data?.error || 'Retry failed'),
  });

  const cancelMut = useMutation({
    mutationFn: (id: number) => api.post(`/inbox/retry-queue/${id}/cancel`),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['inbox-retry-queue'] });
    },
    onError: () => toast.error('Cancel failed'),
  });

  const failed = rows.filter((r) => r.status === 'failed' || r.status === 'pending');

  return (
    <div
      className={cn(
        'rounded-lg border border-surface-200 bg-white p-3 dark:border-surface-700 dark:bg-surface-800',
        className,
      )}
    >
      <div className="mb-2 flex items-center gap-1.5 text-xs font-semibold text-surface-700 dark:text-surface-300">
        <AlertCircle className="h-3.5 w-3.5 text-red-500" />
        Failed Sends
        {failed.length > 0 && (
          <span className="ml-1 inline-flex h-4 min-w-[1rem] items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold text-white">
            {failed.length}
          </span>
        )}
      </div>
      {isLoading ? (
        <div className="text-[11px] text-surface-400">Loading…</div>
      ) : failed.length === 0 ? (
        <div className="text-[11px] text-surface-400">
          All sends delivered cleanly.
        </div>
      ) : (
        <ul className="divide-y divide-surface-100 dark:divide-surface-700">
          {failed.slice(0, 10).map((r) => (
            <li key={r.id} className="py-2 text-[11px]">
              <div className="flex items-center justify-between gap-2">
                <div className="min-w-0 flex-1">
                  <div className="truncate font-medium text-surface-800 dark:text-surface-200">
                    {formatPhone(r.to_phone)}
                  </div>
                  <div className="truncate text-surface-500">
                    {truncate(r.body, 60)}
                  </div>
                  {r.last_error && (
                    <div className="mt-0.5 truncate text-[10px] text-red-500">
                      {truncate(r.last_error, 80)}
                    </div>
                  )}
                  <div className="text-[10px] text-surface-400">
                    attempt #{r.retry_count + 1}
                  </div>
                </div>
                <div className="flex items-center gap-1">
                  <button
                    onClick={() => retryMut.mutate(r.id)}
                    disabled={retryMut.isPending}
                    title="Retry now"
                    className="rounded p-1 text-surface-500 hover:bg-primary-50 hover:text-primary-600 dark:hover:bg-primary-900/20"
                  >
                    <RotateCcw className="h-3.5 w-3.5" />
                  </button>
                  <button
                    onClick={() => cancelMut.mutate(r.id)}
                    disabled={cancelMut.isPending}
                    title="Cancel"
                    className="rounded p-1 text-surface-500 hover:bg-red-50 hover:text-red-600 dark:hover:bg-red-900/20"
                  >
                    <X className="h-3.5 w-3.5" />
                  </button>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
