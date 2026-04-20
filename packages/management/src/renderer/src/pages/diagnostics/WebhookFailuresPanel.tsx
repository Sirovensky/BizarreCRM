import { useCallback, useEffect, useState } from 'react';
import { RefreshCw, AlertCircle, ExternalLink, Filter } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { formatDateTime } from '@/utils/format';
import toast from 'react-hot-toast';

interface Row {
  id: number;
  endpoint: string;
  event: string;
  attempts: number;
  last_error: string | null;
  last_status: number | null;
  created_at: string;
}

interface Summary {
  total: number;
  byEvent: Array<{ event: string; count: number }>;
}

function statusColor(status: number | null): string {
  if (status === null) return 'text-surface-500';
  if (status >= 500) return 'text-red-400';
  if (status >= 400) return 'text-amber-400';
  if (status >= 300) return 'text-sky-400';
  return 'text-emerald-400';
}

export function WebhookFailuresPanel({ slug }: { slug: string }) {
  const [rows, setRows] = useState<Row[]>([]);
  const [summary, setSummary] = useState<Summary | null>(null);
  const [eventFilter, setEventFilter] = useState('');
  const [loading, setLoading] = useState(false);
  const [expanded, setExpanded] = useState<number | null>(null);

  const refresh = useCallback(async () => {
    if (!slug) return;
    setLoading(true);
    try {
      const res = await getAPI().superAdmin.listTenantWebhookFailures({
        slug,
        event: eventFilter || undefined,
        limit: 200,
      });
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        setRows(res.data.rows);
        setSummary(res.data.summary);
      } else if (res.message) {
        toast.error(res.message);
        setRows([]);
        setSummary(null);
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to load webhook failures');
    } finally {
      setLoading(false);
    }
  }, [slug, eventFilter]);

  useEffect(() => { refresh(); }, [refresh]);

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2 flex-wrap text-xs">
        <Filter className="w-3.5 h-3.5 text-surface-500" />
        <input
          type="text"
          placeholder="Filter by event (e.g. ticket_created)"
          value={eventFilter}
          onChange={(e) => setEventFilter(e.target.value.toLowerCase().replace(/[^a-z_]/g, ''))}
          className="px-2 py-1 bg-surface-950 border border-surface-700 rounded text-surface-200 placeholder:text-surface-600 font-mono flex-1 max-w-xs"
        />
        {eventFilter && (
          <button onClick={() => setEventFilter('')} className="text-surface-500 hover:text-surface-300 px-2">
            clear
          </button>
        )}
        <button
          onClick={refresh}
          disabled={loading}
          className="ml-auto p-1.5 rounded text-surface-500 hover:text-surface-200 hover:bg-surface-800 disabled:opacity-50"
          title="Refresh"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </div>

      {summary && (
        <div className="flex items-center gap-2 flex-wrap text-xs">
          <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded border border-red-900/60 bg-red-950/30 text-red-300">
            <AlertCircle className="w-3 h-3" />
            <span className="font-mono">{summary.total}</span>
            <span className="opacity-80">permanent failure{summary.total === 1 ? '' : 's'}</span>
          </span>
          {summary.byEvent.slice(0, 5).map((e) => (
            <button
              key={e.event}
              onClick={() => setEventFilter(e.event)}
              className="inline-flex items-center gap-1 px-2 py-0.5 rounded border border-surface-700 text-surface-400 hover:text-surface-200 hover:border-surface-600"
              title={`Filter to ${e.event}`}
            >
              <span className="font-mono">{e.count}</span>
              <span className="text-surface-500">{e.event}</span>
            </button>
          ))}
        </div>
      )}

      {rows.length === 0 ? (
        <div className="text-center py-8 text-xs text-surface-500">
          {loading ? 'Loading…' : 'No webhook delivery failures — either the table is untouched, or every event delivered successfully.'}
        </div>
      ) : (
        <div className="space-y-1.5">
          {rows.map((r) => {
            const isOpen = expanded === r.id;
            return (
              <div key={r.id} className="rounded border border-surface-800 bg-surface-900/50">
                <button
                  onClick={() => setExpanded(isOpen ? null : r.id)}
                  className="w-full flex items-center justify-between gap-2 p-2.5 text-left hover:bg-surface-800/30 transition-colors"
                >
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-mono text-xs text-surface-200">{r.event}</span>
                      <span className={`font-mono text-[10px] ${statusColor(r.last_status)}`}>
                        {r.last_status ?? 'network error'}
                      </span>
                      <span className="text-[10px] text-surface-500">· {r.attempts} attempt{r.attempts === 1 ? '' : 's'}</span>
                    </div>
                    <div className="flex items-center gap-1 text-[11px] text-surface-500 mt-0.5 truncate">
                      <ExternalLink className="w-3 h-3 flex-shrink-0" />
                      <span className="font-mono truncate">{r.endpoint}</span>
                    </div>
                    {r.last_error && (
                      <div className="text-[11px] text-red-400/80 mt-1 line-clamp-1" title={r.last_error}>
                        {r.last_error}
                      </div>
                    )}
                  </div>
                  <span className="text-[10px] text-surface-500 whitespace-nowrap">{formatDateTime(r.created_at)}</span>
                </button>
                {isOpen && r.last_error && (
                  <div className="px-3 pb-3">
                    <pre className="text-[11px] text-surface-400 bg-surface-950 border border-surface-800 rounded p-2 overflow-x-auto whitespace-pre-wrap break-all">{r.last_error}</pre>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
