import { useState } from 'react';
import { createPortal } from 'react-dom';
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
  ShieldAlert,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { voiceApi, type VoiceCall } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatDateTime } from '@/utils/format';

// WEB-FK-009: Consent confirmation dialog shown before playing a recording
// when the caller was not confirmed to have been informed of recording.
function RecordingConsentDialog({
  open,
  onConfirm,
  onCancel,
}: {
  open: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  if (!open) return null;
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="consent-dialog-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={(e) => { if (e.target === e.currentTarget) onCancel(); }}
    >
      <div className="w-full max-w-sm rounded-xl bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 shadow-2xl p-6">
        <div className="flex items-start gap-3 mb-4">
          <ShieldAlert className="h-5 w-5 text-amber-500 mt-0.5 shrink-0" />
          <div>
            <h3 id="consent-dialog-title" className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-1">
              Confirm Recording Disclosure
            </h3>
            <p className="text-sm text-surface-600 dark:text-surface-400">
              This call has no confirmed disclosure on record. Was the customer informed that this call would be recorded?
            </p>
          </div>
        </div>
        <div className="flex gap-2 justify-end">
          <button
            type="button"
            onClick={onCancel}
            className="px-4 py-2 text-sm font-medium text-surface-600 dark:text-surface-400 hover:text-surface-900 dark:hover:text-surface-100 border border-surface-200 dark:border-surface-700 rounded-lg hover:bg-surface-50 dark:hover:bg-surface-700 transition-colors"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={onConfirm}
            className="px-4 py-2 text-sm font-medium bg-primary-600 text-primary-950 rounded-lg hover:bg-primary-700 transition-colors"
          >
            Yes, Play Recording
          </button>
        </div>
      </div>
    </div>
  );
}

function formatDuration(seconds: number | null): string {
  if (seconds == null || seconds <= 0) return '—';
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

const STATUS_COLORS: Record<string, string> = {
  completed: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  failed: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',
  busy: 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400',
  'no-answer': 'bg-surface-100 text-surface-600 dark:bg-surface-700 dark:text-surface-400',
  in_progress: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
};

function hasRecording(call: VoiceCall): boolean {
  // WEB-FN-013: only check `recording_url`; the on-disk path was removed
  // from the wire/type to avoid leaking `/var/data/tenants/...` layouts.
  return Boolean(call.recording_url);
}

// WEB-W3-023: Fetch a short-lived signed URL from the server, then open it.
// The signed URL is an HMAC-protected token valid for 5 minutes — the raw
// /calls/:id/recording endpoint requires session auth which <audio> src cannot send.
async function openRecordingSecure(callId: number): Promise<void> {
  try {
    const res = await voiceApi.recordingSignedUrl(callId);
    const url = res.data?.data?.url;
    if (!url) throw new Error('No URL returned');
    window.open(url, '_blank', 'noopener,noreferrer');
  } catch {
    toast.error('Could not load recording');
  }
}

interface CallRowProps {
  call: VoiceCall;
}

function CallRow({ call }: CallRowProps) {
  const [loadingRec, setLoadingRec] = useState(false);
  // WEB-FK-009: track whether the consent dialog is open for this row.
  const [showConsentDialog, setShowConsentDialog] = useState(false);
  const isInbound = call.direction === 'inbound';

  // Returns true if we need to show the consent dialog before playing.
  // was_disclosed_to_caller = 1 means confirmed; anything else = needs confirm.
  const needsConsentCheck = !call.was_disclosed_to_caller || call.was_disclosed_to_caller !== 1;

  const doPlay = async () => {
    setLoadingRec(true);
    try {
      await openRecordingSecure(call.id);
    } finally {
      setLoadingRec(false);
    }
  };

  const handlePlay = () => {
    if (needsConsentCheck) {
      setShowConsentDialog(true);
    } else {
      void doPlay();
    }
  };

  const handleConsentConfirm = () => {
    setShowConsentDialog(false);
    void doPlay();
  };

  const handleConsentCancel = () => {
    setShowConsentDialog(false);
  };

  return (
    <>
    {/* WEB-FK-009: render consent dialog via portal so it's not a child of <tr> */}
    {showConsentDialog && createPortal(
      <RecordingConsentDialog
        open={showConsentDialog}
        onConfirm={handleConsentConfirm}
        onCancel={handleConsentCancel}
      />,
      document.body,
    )}
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
        {formatDateTime(call.created_at)}
      </td>
      <td className="px-4 py-3">
        {hasRecording(call) ? (
          <button
            onClick={handlePlay}
            disabled={loadingRec}
            className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium text-primary-700 dark:text-primary-300 border border-primary-200 dark:border-primary-700 rounded-lg hover:bg-primary-50 dark:hover:bg-primary-900/20 transition-colors disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            title="Open recording in new tab"
          >
            {loadingRec ? (
              <Loader2 className="h-3 w-3 animate-spin" />
            ) : (
              <Play className="h-3 w-3" />
            )}
            Play
          </button>
        ) : (
          <span className="text-xs text-surface-300 dark:text-surface-600">—</span>
        )}
      </td>
    </tr>
    </>
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
                  className="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg border border-surface-200 dark:border-surface-700 hover:bg-surface-50 dark:hover:bg-surface-800 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors"
                >
                  <ChevronLeft className="h-4 w-4" />
                  Previous
                </button>
                <button
                  onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                  disabled={page >= totalPages}
                  className="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg border border-surface-200 dark:border-surface-700 hover:bg-surface-50 dark:hover:bg-surface-800 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors"
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
