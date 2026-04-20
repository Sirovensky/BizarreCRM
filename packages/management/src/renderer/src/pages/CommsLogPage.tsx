import { useCallback, useEffect, useState } from 'react';
import { Send, RefreshCw, Mail, MessageSquare, Bell, AlertCircle, CheckCircle2, Clock, Ban } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { Tenant } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { formatDateTime } from '@/utils/format';
import toast from 'react-hot-toast';

interface NotificationRow {
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

const TYPE_ICON: Record<NotificationRow['type'], React.ElementType> = {
  email: Mail,
  sms: MessageSquare,
  push: Bell,
};

const STATUS_COLOR: Record<NotificationRow['status'], string> = {
  pending: 'text-amber-300 bg-amber-950/40 border-amber-900/60',
  sent: 'text-emerald-300 bg-emerald-950/40 border-emerald-900/60',
  failed: 'text-red-300 bg-red-950/40 border-red-900/60',
  cancelled: 'text-surface-400 bg-surface-900 border-surface-700',
};

const STATUS_ICON: Record<NotificationRow['status'], React.ElementType> = {
  pending: Clock,
  sent: CheckCircle2,
  failed: AlertCircle,
  cancelled: Ban,
};

export function CommsLogPage() {
  const [tenants, setTenants] = useState<Tenant[]>([]);
  const [tenantsLoading, setTenantsLoading] = useState(true);
  const [selectedSlug, setSelectedSlug] = useState<string>('');
  const [statusFilter, setStatusFilter] = useState<NotificationRow['status'] | ''>('');
  const [typeFilter, setTypeFilter] = useState<NotificationRow['type'] | ''>('');
  const [rows, setRows] = useState<NotificationRow[]>([]);
  const [summary, setSummary] = useState<Summary | null>(null);
  const [loading, setLoading] = useState(false);

  // Load tenants once for the selector. Use existing super-admin endpoint.
  useEffect(() => {
    let cancelled = false;
    getAPI().superAdmin.listTenants()
      .then((res) => {
        if (cancelled) return;
        if (handleApiResponse(res)) return;
        if (res.success && res.data) {
          setTenants(res.data.tenants);
          // Auto-select the first active tenant so the page shows something useful.
          const first = res.data.tenants.find((t) => t.status === 'active') ?? res.data.tenants[0];
          if (first) setSelectedSlug(first.slug);
        }
      })
      .catch((err) => console.warn('[CommsLog] listTenants failed', err))
      .finally(() => !cancelled && setTenantsLoading(false));
    return () => { cancelled = true; };
  }, []);

  const refresh = useCallback(async () => {
    if (!selectedSlug) return;
    setLoading(true);
    try {
      const res = await getAPI().superAdmin.listTenantNotifications({
        slug: selectedSlug,
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
  }, [selectedSlug, statusFilter, typeFilter]);

  useEffect(() => { refresh(); }, [refresh]);

  return (
    <div className="space-y-4 animate-fade-in">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
          <Send className="w-5 h-5 text-accent-400" />
          Outbound Communications
        </h1>
        <button
          onClick={refresh}
          disabled={loading || !selectedSlug}
          className="p-2 rounded text-surface-400 hover:text-surface-200 hover:bg-surface-800 disabled:opacity-50"
          title="Refresh"
        >
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </div>

      {tenantsLoading ? (
        <p className="text-xs text-surface-500">Loading tenants…</p>
      ) : tenants.length === 0 ? (
        <p className="text-xs text-surface-500">No tenants found.</p>
      ) : (
        <>
          <div className="flex items-center gap-2 flex-wrap text-xs">
            <select
              value={selectedSlug}
              onChange={(e) => setSelectedSlug(e.target.value)}
              className="px-2 py-1 bg-surface-950 border border-surface-700 rounded text-surface-200 font-mono"
            >
              {tenants.map((t) => (
                <option key={t.slug} value={t.slug}>
                  {t.slug} {t.status !== 'active' ? `(${t.status})` : ''}
                </option>
              ))}
            </select>
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value as NotificationRow['status'] | '')}
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
              onChange={(e) => setTypeFilter(e.target.value as NotificationRow['type'] | '')}
              className="px-2 py-1 bg-surface-950 border border-surface-700 rounded text-surface-200"
            >
              <option value="">any type</option>
              <option value="email">email</option>
              <option value="sms">sms</option>
              <option value="push">push</option>
            </select>
          </div>

          {/* Summary chips — always show unfiltered counts. */}
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
            <div className="text-center py-12 text-sm text-surface-500">
              {loading ? 'Loading…' : 'No notifications match the current filter.'}
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b border-surface-800">
                    <th className="text-left py-2 px-3 text-surface-500 font-medium">Created</th>
                    <th className="text-left py-2 px-3 text-surface-500 font-medium">Type</th>
                    <th className="text-left py-2 px-3 text-surface-500 font-medium">Recipient</th>
                    <th className="text-left py-2 px-3 text-surface-500 font-medium">Subject / Body</th>
                    <th className="text-left py-2 px-3 text-surface-500 font-medium">Status</th>
                    <th className="text-left py-2 px-3 text-surface-500 font-medium">Sent</th>
                    <th className="text-right py-2 px-3 text-surface-500 font-medium">Retries</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => {
                    const TypeIcon = TYPE_ICON[r.type];
                    const StatusIcon = STATUS_ICON[r.status];
                    return (
                      <tr key={r.id} className="border-b border-surface-800/50 hover:bg-surface-800/30">
                        <td className="py-2 px-3 text-surface-500 whitespace-nowrap">{formatDateTime(r.created_at)}</td>
                        <td className="py-2 px-3 text-surface-300">
                          <span className="inline-flex items-center gap-1">
                            <TypeIcon className="w-3.5 h-3.5 text-surface-500" />
                            {r.type}
                          </span>
                        </td>
                        <td className="py-2 px-3 font-mono text-surface-300">{r.recipient}</td>
                        <td className="py-2 px-3 text-surface-400 max-w-md truncate" title={r.subject ?? ''}>
                          {r.subject ?? '—'}
                          {r.error && (
                            <div className="text-[11px] text-red-400 mt-0.5 truncate" title={r.error}>
                              {r.error}
                            </div>
                          )}
                        </td>
                        <td className="py-2 px-3">
                          <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded border text-[10px] font-medium ${STATUS_COLOR[r.status]}`}>
                            <StatusIcon className="w-3 h-3" />
                            {r.status}
                          </span>
                        </td>
                        <td className="py-2 px-3 text-surface-500 whitespace-nowrap">
                          {r.sent_at ? formatDateTime(r.sent_at) : '—'}
                        </td>
                        <td className="py-2 px-3 text-right text-surface-400 font-mono">{r.retry_count}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </>
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
