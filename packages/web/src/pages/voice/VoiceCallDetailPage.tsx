/**
 * WEB-UIUX-381: voice-call detail page so the list rows can link to a
 * single-call view (audio playback + metadata + linked entity).
 */
import { useParams, Link, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { ArrowLeft, Phone, PhoneIncoming, PhoneOutgoing, Loader2, AlertTriangle, Download } from 'lucide-react';
import { voiceApi } from '@/api/endpoints';
import { formatDateTime } from '@/utils/format';
import toast from 'react-hot-toast';

interface CallRow {
  id: number;
  direction: 'inbound' | 'outbound' | string;
  status: string;
  from_phone: string | null;
  to_phone: string | null;
  conv_phone: string | null;
  duration_seconds: number | null;
  created_at: string;
  user_id: number | null;
  user_first_name: string | null;
  user_last_name: string | null;
  entity_type: string | null;
  entity_id: number | null;
  has_recording?: boolean | number | null;
  recording_path?: string | null;
  notes?: string | null;
}

function formatDuration(secs: number | null): string {
  if (!Number.isFinite(secs)) return '—';
  const total = Math.max(0, Math.round(Number(secs)));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${String(s).padStart(2, '0')}`;
}

function entityLink(entity_type: string | null, entity_id: number | null): { to: string; label: string } | null {
  if (!entity_type || !entity_id) return null;
  switch (entity_type) {
    case 'customer': return { to: `/customers/${entity_id}`, label: `Customer #${entity_id}` };
    case 'ticket':   return { to: `/tickets/${entity_id}`,   label: `Ticket #${entity_id}` };
    case 'lead':     return { to: `/leads/${entity_id}`,     label: `Lead #${entity_id}` };
    case 'invoice':  return { to: `/invoices/${entity_id}`,  label: `Invoice #${entity_id}` };
    case 'estimate': return { to: `/estimates/${entity_id}`, label: `Estimate #${entity_id}` };
    default: return null;
  }
}

export function VoiceCallDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const callId = Number(id);
  const [playUrl, setPlayUrl] = useState<string | null>(null);

  const { data, isLoading, isError, refetch, error } = useQuery({
    queryKey: ['voice-call', callId],
    enabled: Number.isFinite(callId) && callId > 0,
    queryFn: async () => {
      const res = await voiceApi.callDetail(callId);
      return (res.data?.data ?? res.data) as CallRow;
    },
  });

  const playMut = useMutation({
    mutationFn: () => voiceApi.recordingSignedUrl(callId),
    onSuccess: (res) => {
      const url = res.data?.data?.url;
      if (url) setPlayUrl(url);
      else toast.error('Recording not available');
    },
    onError: (err: any) => {
      toast.error(err?.response?.data?.message || 'Could not load recording');
    },
  });

  const link = data ? entityLink(data.entity_type, data.entity_id) : null;
  const inbound = data?.direction === 'inbound';

  return (
    <div className="p-6">
      <button
        onClick={() => navigate('/voice')}
        className="mb-4 inline-flex items-center gap-1 text-sm text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200"
      >
        <ArrowLeft className="h-4 w-4" /> Back to calls
      </button>

      {isLoading && (
        <div className="flex items-center gap-2 text-sm text-surface-500 dark:text-surface-400">
          <Loader2 className="h-4 w-4 animate-spin" /> Loading call…
        </div>
      )}
      {isError && (
        <div className="flex items-center gap-2 rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-800 dark:bg-red-900/20 dark:text-red-300">
          <AlertTriangle className="h-4 w-4" />
          {(error as any)?.response?.status === 404
            ? 'Call not found.'
            : (error as any)?.response?.data?.message || 'Failed to load call.'}
          <button onClick={() => refetch()} className="ml-2 underline">Retry</button>
        </div>
      )}

      {data && (
        <div className="space-y-4">
          <div className="flex items-start justify-between gap-4">
            <div className="flex items-start gap-3">
              <div className={`mt-1 rounded-full p-2 ${inbound ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-300' : 'bg-primary-100 text-primary-700 dark:bg-primary-900/30 dark:text-primary-300'}`}>
                {inbound ? <PhoneIncoming className="h-5 w-5" /> : <PhoneOutgoing className="h-5 w-5" />}
              </div>
              <div>
                <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">
                  <span className="capitalize">{data.direction}</span> call · {data.conv_phone || data.from_phone || data.to_phone || '—'}
                </h1>
                <p className="text-sm text-surface-500 dark:text-surface-400">
                  {formatDateTime(data.created_at)} · status <span className="font-mono">{data.status}</span> · duration {formatDuration(data.duration_seconds)}
                </p>
              </div>
            </div>
          </div>

          <div className="grid gap-3 rounded-xl border border-surface-200 bg-white p-4 text-sm dark:border-surface-700 dark:bg-surface-800 sm:grid-cols-2">
            <div>
              <div className="text-xs uppercase tracking-wide text-surface-400 dark:text-surface-500">From</div>
              <div className="font-mono text-surface-900 dark:text-surface-100">{data.from_phone || '—'}</div>
            </div>
            <div>
              <div className="text-xs uppercase tracking-wide text-surface-400 dark:text-surface-500">To</div>
              <div className="font-mono text-surface-900 dark:text-surface-100">{data.to_phone || '—'}</div>
            </div>
            <div>
              <div className="text-xs uppercase tracking-wide text-surface-400 dark:text-surface-500">Operator</div>
              <div className="text-surface-900 dark:text-surface-100">
                {data.user_id
                  ? [data.user_first_name, data.user_last_name].filter(Boolean).join(' ') || `#${data.user_id}`
                  : '—'}
              </div>
            </div>
            <div>
              <div className="text-xs uppercase tracking-wide text-surface-400 dark:text-surface-500">Linked</div>
              <div>
                {link ? (
                  <Link to={link.to} className="text-primary-600 dark:text-primary-400 hover:underline">{link.label}</Link>
                ) : (
                  <span className="text-surface-500 dark:text-surface-400">—</span>
                )}
              </div>
            </div>
            {data.notes && (
              <div className="sm:col-span-2">
                <div className="text-xs uppercase tracking-wide text-surface-400 dark:text-surface-500">Notes</div>
                <div className="whitespace-pre-wrap text-surface-900 dark:text-surface-100">{data.notes}</div>
              </div>
            )}
          </div>

          {data.has_recording ? (
            <div className="rounded-xl border border-surface-200 bg-white p-4 dark:border-surface-700 dark:bg-surface-800">
              <div className="flex items-center justify-between gap-3 mb-2">
                <h2 className="flex items-center gap-2 text-sm font-semibold text-surface-900 dark:text-surface-100">
                  <Phone className="h-4 w-4" /> Recording
                </h2>
                {!playUrl && (
                  <button
                    type="button"
                    onClick={() => playMut.mutate()}
                    disabled={playMut.isPending}
                    className="rounded-md border border-primary-200 px-3 py-1 text-xs font-medium text-primary-700 hover:bg-primary-50 disabled:opacity-50 dark:border-primary-700 dark:text-primary-300 dark:hover:bg-primary-900/30"
                  >
                    {playMut.isPending ? 'Loading…' : 'Load recording'}
                  </button>
                )}
              </div>
              {playUrl && (
                <div className="space-y-2">
                  <audio controls src={playUrl} className="w-full" />
                  <a
                    href={playUrl}
                    download
                    className="inline-flex items-center gap-1 text-xs text-primary-600 dark:text-primary-400 hover:underline"
                  >
                    <Download className="h-3 w-3" /> Download
                  </a>
                </div>
              )}
            </div>
          ) : (
            <div className="rounded-xl border border-surface-200 bg-surface-50 p-4 text-sm text-surface-500 dark:border-surface-700 dark:bg-surface-800/50 dark:text-surface-400">
              No recording for this call.
            </div>
          )}
        </div>
      )}
    </div>
  );
}
