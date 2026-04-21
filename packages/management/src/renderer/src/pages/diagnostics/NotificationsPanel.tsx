import { useCallback, useEffect, useState } from 'react';
import { RefreshCw, Mail, MessageSquare, Bell, AlertCircle, CheckCircle2, Clock, Ban, Download } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { formatDateTime } from '@/utils/format';
import { downloadCsv, toCsv } from '@/utils/csv';
import toast from 'react-hot-toast';

interface Row {
  id: number;
  type: 'sms' | 'email' | 'push';
  recipient: string;
  subject: string | null;
  status: 'pending' | 'sent' | 'failed' | 'cancelled';
  error: string | null;
  retry_count: number;
  scheduled_at: string | null;
  sent_at: string | null;
  created_at: string;
}

interface Summary { total: number; pending: number; sent: number; failed: number; cancelled: number }

const TYPE_ICON: Record<Row['type'], React.ElementType> = {
  email: Mail,
  sms: MessageSquare,
  push: Bell,
};

const STATUS_COLOR: Record<Row['status'], string> = {
  pending: 'text-amber-300 bg-amber-950/40 border-amber-900/60',
  sent: 'text-emerald-300 bg-emerald-950/40 border-emerald-900/60',
  failed: 'text-red-300 bg-red-950/40 border-red-900/60',
  cancelled: 'text-surface-400 bg-surface-900 border-surface-700',
};

const STATUS_ICON: Record<Row['status'], React.ElementType> = {
  pending: Clock,
  sent: CheckCircle2,
  failed: AlertCircle,
  cancelled: Ban,
};

export function NotificationsPanel({ slug }: { slug: string }) {
  const [rows, setRows] = useState<Row[]>([]);
  const [summary, setSummary] = useState<Summary | null>(null);
  const [statusFilter, setStatusFilter] = useState<Row['status'] | ''>('');
  const [typeFilter, setTypeFilter] = useState<Row['type'] | ''>('');
  const [loading, setLoading] = useState(false);

  const refresh = useCallback(async () => {
    if (!slug) return;
    setLoading(true);
    try {
      const res = await getAPI().superAdmin.listTenantNotifications({
        slug,
        status: statusFilter || undefined,
        type: typeFilter || undefined,
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
      toast.error(err instanceof Error ? err.message : 'Failed to load notifications');
    } finally {
      setLoading(false);
    }
  }, [slug, statusFilter, typeFilter]);

  useEffect(() => { refresh(); }, [refresh]);

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2 flex-wrap text-xs">
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value as Row['status'] | '')}
          className="px-2 py-1 bg-surface-950 border border-surface-700 rounded text-surface-200"
        >
          <option value="">any status</option>
          <option value="pending">pending</option>
          <option value="sent">sent</option>
          <option value="failed">failed</option>
          <option value="cancelled">cancelled</option>
        </select>
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value as Row['type'] | '')}
          className="px-2 py-1 bg-surface-950 border border-surface-700 rounded text-surface-200"
        >
          <option value="">any type</option>
          <option value="email">email</option>
          <option value="sms">sms</option>
          <option value="push">push</option>
        </select>
        <div className="ml-auto flex items-center gap-1.5">
          <button
            onClick={() => {
              if (rows.length === 0) { toast('Nothing to export'); return; }
              const csv = toCsv(
                ['created_at', 'type', 'recipient', 'subject', 'status', 'error', 'retry_count', 'sent_at'],
                rows as unknown as Record<string, unknown>[],
              );
              downloadCsv(`notifications-${new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-')}.csv`, csv);
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
          <SummaryChip label="sent" count={summary.sent} color="border-emerald-900/60 text-emerald-300 bg-emerald-950/30" />
          <SummaryChip label="pending" count={summary.pending} color="border-amber-900/60 text-amber-300 bg-amber-950/30" />
          <SummaryChip label="failed" count={summary.failed} color="border-red-900/60 text-red-300 bg-red-950/30" />
          <SummaryChip label="cancelled" count={summary.cancelled} color="border-surface-700 text-surface-400" />
        </div>
      )}

      {rows.length === 0 ? (
        <div className="text-center py-8 text-xs text-surface-500">
          {loading ? 'Loading…' : 'No notifications match the current filter.'}
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-surface-800">
                <th className="text-left py-2 px-2 text-surface-500 font-medium">Created</th>
                <th className="text-left py-2 px-2 text-surface-500 font-medium">Type</th>
                <th className="text-left py-2 px-2 text-surface-500 font-medium">Recipient</th>
                <th className="text-left py-2 px-2 text-surface-500 font-medium">Subject / Error</th>
                <th className="text-left py-2 px-2 text-surface-500 font-medium">Status</th>
                <th className="text-left py-2 px-2 text-surface-500 font-medium">Sent</th>
                <th className="text-right py-2 px-2 text-surface-500 font-medium">Retries</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => {
                const TypeIcon = TYPE_ICON[r.type];
                const StatusIcon = STATUS_ICON[r.status];
                return (
                  <tr key={r.id} className="border-b border-surface-800/50 hover:bg-surface-800/30">
                    <td className="py-1.5 px-2 text-surface-500 whitespace-nowrap">{formatDateTime(r.created_at)}</td>
                    <td className="py-1.5 px-2 text-surface-300">
                      <span className="inline-flex items-center gap-1">
                        <TypeIcon className="w-3.5 h-3.5 text-surface-500" />
                        {r.type}
                      </span>
                    </td>
                    <td className="py-1.5 px-2 font-mono text-surface-300">{r.recipient}</td>
                    <td className="py-1.5 px-2 text-surface-400 max-w-md truncate" title={r.subject ?? r.error ?? ''}>
                      {r.subject ?? '—'}
                      {r.error && (
                        <div className="text-[11px] text-red-400 mt-0.5 truncate" title={r.error}>
                          {r.error}
                        </div>
                      )}
                    </td>
                    <td className="py-1.5 px-2">
                      <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded border text-[10px] font-medium ${STATUS_COLOR[r.status]}`}>
                        <StatusIcon className="w-3 h-3" />
                        {r.status}
                      </span>
                    </td>
                    <td className="py-1.5 px-2 text-surface-500 whitespace-nowrap">
                      {r.sent_at ? formatDateTime(r.sent_at) : '—'}
                    </td>
                    <td className="py-1.5 px-2 text-right text-surface-400 font-mono">{r.retry_count}</td>
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

function SummaryChip({ label, count, color }: { label: string; count: number; color: string }) {
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded border ${color}`}>
      <span className="font-mono">{count}</span>
      <span className="text-surface-500">{label}</span>
    </span>
  );
}
