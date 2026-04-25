import { useCallback, useEffect, useState } from 'react';
import { RefreshCw, CheckCircle2, XCircle, SkipForward, Repeat, Download } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { formatDateTime } from '@/utils/format';
import { downloadCsv, toCsv } from '@/utils/csv';
import toast from 'react-hot-toast';
import { formatApiError } from '@/utils/apiError';

interface Row {
  id: number;
  automation_id: number;
  automation_name: string | null;
  trigger_event: string;
  action_type: string | null;
  target_entity_type: string | null;
  target_entity_id: number | null;
  status: 'success' | 'failure' | 'skipped' | 'loop_rejected';
  error_message: string | null;
  depth: number;
  created_at: string;
}

interface Summary {
  total: number;
  success: number;
  failure: number;
  skipped: number;
  loop_rejected: number;
}

const STATUS_ICON: Record<Row['status'], React.ElementType> = {
  success: CheckCircle2,
  failure: XCircle,
  skipped: SkipForward,
  loop_rejected: Repeat,
};

const STATUS_COLOR: Record<Row['status'], string> = {
  success: 'text-emerald-300 bg-emerald-950/40 border-emerald-900/60',
  failure: 'text-red-300 bg-red-950/40 border-red-900/60',
  skipped: 'text-surface-400 bg-surface-900 border-surface-700',
  loop_rejected: 'text-amber-300 bg-amber-950/40 border-amber-900/60',
};

export function AutomationRunsPanel({ slug }: { slug: string }) {
  const [rows, setRows] = useState<Row[]>([]);
  const [summary, setSummary] = useState<Summary | null>(null);
  const [statusFilter, setStatusFilter] = useState<Row['status'] | ''>('');
  const [loading, setLoading] = useState(false);

  const refresh = useCallback(async () => {
    if (!slug) return;
    setLoading(true);
    try {
      const res = await getAPI().superAdmin.listTenantAutomationRuns({
        slug,
        status: statusFilter || undefined,
        limit: 200,
      });
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        setRows(res.data.rows);
        setSummary(res.data.summary);
      } else if (res.message) {
        toast.error(formatApiError(res));
        setRows([]);
        setSummary(null);
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to load automation runs');
    } finally {
      setLoading(false);
    }
  }, [slug, statusFilter]);

  useEffect(() => { refresh(); }, [refresh]);

  const successRate = summary && summary.total > 0
    ? Math.round((summary.success / summary.total) * 100)
    : null;

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2 flex-wrap text-xs">
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value as Row['status'] | '')}
          className="px-2 py-1 bg-surface-950 border border-surface-700 rounded text-surface-200"
        >
          <option value="">any status</option>
          <option value="success">success</option>
          <option value="failure">failure</option>
          <option value="skipped">skipped</option>
          <option value="loop_rejected">loop_rejected</option>
        </select>
        <div className="ml-auto flex items-center gap-1.5">
          <button
            onClick={() => {
              if (rows.length === 0) { toast('Nothing to export'); return; }
              const csv = toCsv(
                ['created_at', 'automation_id', 'automation_name', 'trigger_event', 'action_type', 'target_entity_type', 'target_entity_id', 'status', 'depth', 'error_message'],
                rows,
              );
              downloadCsv(`automation-runs-${new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-')}.csv`, csv);
              toast.success(`Exported ${rows.length} rows`);
            }}
            className="inline-flex items-center gap-1 px-2 py-1 text-[11px] text-surface-400 border border-surface-700 rounded hover:bg-surface-800"
            title="Export current rows to CSV"
          >
            <Download className="w-3 h-3" />
            CSV
          </button>
          <button
            onClick={refresh}
            disabled={loading}
            className="p-1.5 rounded text-surface-500 hover:text-surface-200 hover:bg-surface-800 disabled:opacity-50"
            title="Refresh"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      {summary && (
        <div className="flex items-center gap-2 flex-wrap text-xs">
          <SummaryChip label="total" count={summary.total} color="border-surface-700 text-surface-300" />
          <SummaryChip label="success" count={summary.success} color="border-emerald-900/60 text-emerald-300 bg-emerald-950/30" onClick={() => setStatusFilter((f) => f === 'success' ? '' : 'success')} active={statusFilter === 'success'} />
          <SummaryChip label="failure" count={summary.failure} color="border-red-900/60 text-red-300 bg-red-950/30" onClick={() => setStatusFilter((f) => f === 'failure' ? '' : 'failure')} active={statusFilter === 'failure'} />
          <SummaryChip label="skipped" count={summary.skipped} color="border-surface-700 text-surface-400" onClick={() => setStatusFilter((f) => f === 'skipped' ? '' : 'skipped')} active={statusFilter === 'skipped'} />
          {summary.loop_rejected > 0 && (
            <SummaryChip label="loop_rejected" count={summary.loop_rejected} color="border-amber-900/60 text-amber-300 bg-amber-950/30" onClick={() => setStatusFilter((f) => f === 'loop_rejected' ? '' : 'loop_rejected')} active={statusFilter === 'loop_rejected'} />
          )}
          {successRate !== null && (
            <span className="text-surface-500">
              <span className="font-mono text-surface-200">{successRate}%</span> success rate
            </span>
          )}
        </div>
      )}

      {rows.length === 0 ? (
        <div className="text-center py-8 text-xs text-surface-500">
          {loading ? 'Loading…' : 'No automation runs recorded — either automations are disabled, or the table is untouched.'}
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-surface-800">
                <th className="text-left py-2 px-2 text-surface-500 font-medium">Time</th>
                <th className="text-left py-2 px-2 text-surface-500 font-medium">Automation</th>
                <th className="text-left py-2 px-2 text-surface-500 font-medium">Trigger</th>
                <th className="text-left py-2 px-2 text-surface-500 font-medium">Action</th>
                <th className="text-left py-2 px-2 text-surface-500 font-medium">Target</th>
                <th className="text-left py-2 px-2 text-surface-500 font-medium">Status</th>
                <th className="text-left py-2 px-2 text-surface-500 font-medium">Error</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => {
                const StatusIcon = STATUS_ICON[r.status];
                return (
                  <tr key={r.id} className="border-b border-surface-800/50 hover:bg-surface-800/30">
                    <td className="py-1.5 px-2 text-surface-500 whitespace-nowrap">{formatDateTime(r.created_at)}</td>
                    <td className="py-1.5 px-2 text-surface-200">
                      <span className="font-mono">{r.automation_name ?? `#${r.automation_id}`}</span>
                      {r.depth > 0 && (
                        <span className="ml-1 text-[10px] text-amber-400/80">depth {r.depth}</span>
                      )}
                    </td>
                    <td className="py-1.5 px-2 font-mono text-surface-400">{r.trigger_event}</td>
                    <td className="py-1.5 px-2 font-mono text-surface-400">{r.action_type ?? '—'}</td>
                    <td className="py-1.5 px-2 text-surface-500 whitespace-nowrap">
                      {r.target_entity_type
                        ? `${r.target_entity_type}${r.target_entity_id ? ` #${r.target_entity_id}` : ''}`
                        : '—'}
                    </td>
                    <td className="py-1.5 px-2">
                      <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded border text-[10px] font-medium ${STATUS_COLOR[r.status]}`}>
                        <StatusIcon className="w-3 h-3" />
                        {r.status}
                      </span>
                    </td>
                    <td className="py-1.5 px-2 text-red-400/80 max-w-xs truncate" title={r.error_message ?? ''}>
                      {r.error_message ?? '—'}
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

function SummaryChip({ label, count, color, onClick, active }: { label: string; count: number; color: string; onClick?: () => void; active?: boolean }) {
  if (onClick) {
    return (
      <button
        type="button"
        onClick={onClick}
        aria-pressed={active}
        aria-label={`Filter by ${label}`}
        className={`inline-flex items-center gap-1 px-2 py-0.5 rounded border transition-opacity ${color} ${active ? 'ring-1 ring-current' : 'opacity-80 hover:opacity-100'}`}
      >
        <span className="font-mono">{count}</span>
        <span className="text-surface-500">{label}</span>
      </button>
    );
  }
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded border ${color}`}>
      <span className="font-mono">{count}</span>
      <span className="text-surface-500">{label}</span>
    </span>
  );
}
