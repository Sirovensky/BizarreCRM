import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import {
  Phone,
  PhoneIncoming,
  PhoneOutgoing,
  Loader2,
  Play,
  AlertCircle,
  ChevronLeft,
  ChevronRight,
} from 'lucide-react';
import { voiceApi, type VoiceCall } from '@/api/endpoints';
import { cn } from '@/utils/cn';

function formatDuration(seconds: number | null): string {
  if (seconds == null || seconds <= 0) return '—';
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

function formatDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

const STATUS_COLORS: Record<string, string> = {
  completed: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  failed: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',
  busy: 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400',
  'no-answer': 'bg-surface-100 text-surface-600 dark:bg-surface-700 dark:text-surface-400',
  in_progress: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
};

function hasRecording(call: VoiceCall): boolean {
  return Boolean(call.recording_url || call.recording_local_path);
}

function openRecording(callId: number): void {
  window.open(voiceApi.recordingPath(callId), '_blank', 'noopener,noreferrer');
}

interface CallRowProps {
  call: VoiceCall;
}

function CallRow({ call }: CallRowProps) {
  const isInbound = call.direction === 'inbound';

  return (
    <tr className="border-t border-surface-100 dark:border-surface-800 hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors">
      <td className="px-4 py-3 text-sm text-surface-700 dark:text-surface-300 font-mono">
        {call.from_number || '—'}
      </td>
      <td className="px-4 py-3 text-sm text-surface-700 dark:text-surface-300 font-mono">
        {call.to_number || '—'}
      </td>
      <td className="px-4 py-3">
        <span
          className={cn(
            'inline-flex items-center gap-1 text-xs font-medium',
            isInbound ? 'text-blue-600 dark:text-blue-400' : 'text-surface-600 dark:text-surface-400',
          )}
        >
          {isInbound ? (
            <PhoneIncoming className="h-3.5 w-3.5" />
          ) : (
            <PhoneOutgoing className="h-3.5 w-3.5" />
          )}
          {isInbound ? 'Inbound' : 'Outbound'}
        </span>
      </td>
      <td className="px-4 py-3 text-sm text-surface-600 dark:text-surface-400 tabular-nums">
        {formatDuration(call.duration)}
      </td>
      <td className="px-4 py-3">
        <span
          className={cn(
            'px-2 py-0.5 rounded-full text-xs font-medium',
            STATUS_COLORS[call.status] ?? 'bg-surface-100 text-surface-600 dark:bg-surface-700 dark:text-surface-400',
          )}
        >
          {call.status}
        </span>
      </td>
      <td className="px-4 py-3 text-xs text-surface-500 dark:text-surface-400 whitespace-nowrap">
        {formatDate(call.created_at)}
      </td>
      <td className="px-4 py-3">
        {hasRecording(call) ? (
          <button
            onClick={() => openRecording(call.id)}
            className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium text-primary-700 dark:text-primary-300 border border-primary-200 dark:border-primary-700 rounded-lg hover:bg-primary-50 dark:hover:bg-primary-900/20 transition-colors"
            title="Open recording in new tab"
          >
            <Play className="h-3 w-3" />
            Play
          </button>
        ) : (
          <span className="text-xs text-surface-300 dark:text-surface-600">—</span>
        )}
      </td>
    </tr>
  );
}

export function VoiceCallsListPage() {
  const [page, setPage] = useState(1);
  const pageSize = 25;

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ['voice-calls', page],
    queryFn: () => voiceApi.calls({ page, pagesize: pageSize }),
    staleTime: 30_000,
  });

  const calls = data?.data?.data?.calls ?? [];
  const pagination = data?.data?.data?.pagination;
  const totalPages = pagination?.total_pages ?? 1;

  return (
    <div>
      <div className="mb-6 flex items-center gap-3">
        <Phone className="h-6 w-6 text-primary-600" />
        <div>
          <h1 className="text-xl font-bold text-surface-900 dark:text-surface-100">Voice Calls</h1>
          {pagination && (
            <p className="text-sm text-surface-500 dark:text-surface-400">
              {pagination.total} call{pagination.total !== 1 ? 's' : ''}
            </p>
          )}
        </div>
      </div>

      {isError && (
        <div className="flex flex-col items-center justify-center py-16 gap-3">
          <AlertCircle className="h-10 w-10 text-red-400" />
          <p className="text-sm text-surface-500">Failed to load calls.</p>
          <button
            onClick={() => refetch()}
            className="px-4 py-2 text-sm text-primary-600 border border-primary-200 rounded-lg hover:bg-primary-50"
          >
            Retry
          </button>
        </div>
      )}

      {isLoading && (
        <div className="flex justify-center py-16">
          <Loader2 className="h-8 w-8 animate-spin text-primary-400" />
        </div>
      )}

      {!isLoading && !isError && calls.length === 0 && (
        <div className="flex flex-col items-center justify-center py-20 gap-3 text-center">
          <Phone className="h-12 w-12 text-surface-300 dark:text-surface-600" />
          <p className="text-base font-medium text-surface-600 dark:text-surface-400">
            No voice calls yet.
          </p>
          <p className="text-sm text-surface-400 dark:text-surface-500">
            Configure voice in{' '}
            <Link
              to="/settings/sms-voice"
              className="text-primary-600 hover:text-primary-700 underline"
            >
              Settings &rarr; SMS &amp; Voice
            </Link>
            .
          </p>
        </div>
      )}

      {!isLoading && !isError && calls.length > 0 && (
        <>
          <div className="overflow-x-auto rounded-xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-surface-50 dark:bg-surface-800/80">
                  <th className="px-4 py-3 text-left text-xs font-semibold text-surface-500 uppercase tracking-wide">From</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-surface-500 uppercase tracking-wide">To</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-surface-500 uppercase tracking-wide">Direction</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-surface-500 uppercase tracking-wide">Duration</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-surface-500 uppercase tracking-wide">Status</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-surface-500 uppercase tracking-wide">Started At</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-surface-500 uppercase tracking-wide">Actions</th>
                </tr>
              </thead>
              <tbody>
                {calls.map((call) => (
                  <CallRow key={call.id} call={call} />
                ))}
              </tbody>
            </table>
          </div>

          {totalPages > 1 && (
            <div className="mt-4 flex items-center justify-between text-sm text-surface-500">
              <span>
                Page {page} of {totalPages}
              </span>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  disabled={page <= 1}
                  className="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg border border-surface-200 dark:border-surface-700 hover:bg-surface-50 dark:hover:bg-surface-800 disabled:opacity-40 transition-colors"
                >
                  <ChevronLeft className="h-4 w-4" />
                  Previous
                </button>
                <button
                  onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                  disabled={page >= totalPages}
                  className="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg border border-surface-200 dark:border-surface-700 hover:bg-surface-50 dark:hover:bg-surface-800 disabled:opacity-40 transition-colors"
                >
                  Next
                  <ChevronRight className="h-4 w-4" />
                </button>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
