import { useCallback, useEffect, useMemo, useState } from 'react';
import { ScrollText, RefreshCw, Filter, Trash2, Download } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { CopyText } from '@/components/CopyText';
import { formatDateTime } from '@/utils/format';
import { downloadCsv, toCsv } from '@/utils/csv';
import toast from 'react-hot-toast';

interface AuditEntry {
  id: number;
  admin_username: string;
  action: string;
  details: string;
  ip_address: string;
  created_at: string;
}

export function AuditLogPage() {
  const [entries, setEntries] = useState<AuditEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionFilter, setActionFilter] = useState('');
  const [textFilter, setTextFilter] = useState('');

  const refresh = useCallback(async () => {
    try {
      // AUDIT-MGT-008: pass typed object; query string is built in main process.
      // Server-side `action` filter narrows to one audit event type; the
      // free-text filter is applied client-side against admin/details/ip.
      const params: { limit: number; action?: string } = { limit: 200 };
      if (actionFilter) params.action = actionFilter;
      const res = await getAPI().superAdmin.getAuditLog(params);
      // AUDIT-MGT-010: detect 401 and trigger global auto-logout.
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        const list = Array.isArray(res.data) ? res.data : (res.data as { logs: AuditEntry[] }).logs ?? [];
        setEntries(list as AuditEntry[]);
      }
    } catch {
      toast.error('Failed to load audit log');
    } finally {
      setLoading(false);
    }
  }, [actionFilter]);

  useEffect(() => { refresh(); }, [refresh]);

  // Distinct action names gathered from the currently-loaded batch — feeds
  // the action dropdown so operators do not need to remember "update_config"
  // vs "super_admin_tenant_update". Sorted for predictable scan order.
  const actionOptions = useMemo(() => {
    const set = new Set<string>();
    for (const e of entries) set.add(e.action);
    return [...set].sort();
  }, [entries]);

  const filtered = useMemo(() => {
    if (!textFilter.trim()) return entries;
    const needle = textFilter.toLowerCase();
    return entries.filter((e) =>
      e.admin_username?.toLowerCase().includes(needle) ||
      e.details?.toLowerCase().includes(needle) ||
      e.ip_address?.toLowerCase().includes(needle) ||
      e.action?.toLowerCase().includes(needle)
    );
  }, [entries, textFilter]);

  if (loading) {
    return <div className="flex items-center justify-center py-20"><RefreshCw className="w-5 h-5 text-surface-500 animate-spin" /></div>;
  }

  return (
    <div className="space-y-3 lg:space-y-5 animate-fade-in">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <h1 className="text-base lg:text-lg font-bold text-surface-100 flex items-center gap-2">
          <ScrollText className="w-5 h-5 text-accent-400" />
          Audit Log
          <span className="text-xs text-surface-500 font-normal">
            ({filtered.length}{filtered.length !== entries.length ? ` of ${entries.length}` : ''})
          </span>
        </h1>
        <div className="flex items-center gap-2">
          <button
            onClick={() => {
              if (filtered.length === 0) { toast('Nothing to export'); return; }
              const csv = toCsv(
                ['created_at', 'admin_username', 'action', 'details', 'ip_address'],
                filtered as unknown as Record<string, unknown>[],
              );
              const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-');
              downloadCsv(`audit-log-${stamp}.csv`, csv);
              toast.success(`Exported ${filtered.length} rows`);
            }}
            className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs text-surface-400 border border-surface-700 rounded hover:bg-surface-800"
            title="Export the currently filtered rows to CSV"
          >
            <Download className="w-3.5 h-3.5" />
            Export CSV
          </button>
          <button onClick={refresh} className="p-2 rounded-lg text-surface-400 hover:text-surface-200 hover:bg-surface-800">
            <RefreshCw className="w-4 h-4" />
          </button>
        </div>
      </div>

      <div className="flex items-center gap-2 flex-wrap text-xs">
        <Filter className="w-3.5 h-3.5 text-surface-500" />
        <select
          value={actionFilter}
          onChange={(e) => setActionFilter(e.target.value)}
          className="px-2 py-1 bg-surface-950 border border-surface-700 rounded text-surface-200 font-mono"
        >
          <option value="">any action</option>
          {actionOptions.map((a) => <option key={a} value={a}>{a}</option>)}
        </select>
        <input
          type="text"
          value={textFilter}
          onChange={(e) => setTextFilter(e.target.value)}
          placeholder="Filter admin / IP / details…"
          className="flex-1 min-w-[180px] max-w-sm px-2 py-1 bg-surface-950 border border-surface-700 rounded text-surface-200 placeholder:text-surface-600"
        />
        {(actionFilter || textFilter) && (
          <button
            onClick={() => { setActionFilter(''); setTextFilter(''); }}
            className="inline-flex items-center gap-1 px-2 py-1 text-surface-500 hover:text-surface-300 border border-surface-800 rounded"
          >
            <Trash2 className="w-3 h-3" />
            clear
          </button>
        )}
      </div>

      {filtered.length === 0 ? (
        <div className="text-center py-12 text-sm text-surface-500">
          {entries.length === 0 ? 'No audit entries found' : 'No entries match the current filter.'}
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-surface-800">
                <th className="text-left py-2 px-3 text-surface-500 font-medium">Time</th>
                <th className="text-left py-2 px-3 text-surface-500 font-medium">Admin</th>
                <th className="text-left py-2 px-3 text-surface-500 font-medium">Action</th>
                <th className="text-left py-2 px-3 text-surface-500 font-medium">Details</th>
                <th className="text-left py-2 px-3 text-surface-500 font-medium">IP</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((e) => (
                <tr key={e.id} className="border-b border-surface-800/50 hover:bg-surface-800/30">
                  <td className="py-1.5 px-2 text-surface-500 whitespace-nowrap">{formatDateTime(e.created_at)}</td>
                  <td className="py-1.5 px-2 text-surface-300 font-medium">
                    <button
                      onClick={() => setTextFilter(e.admin_username)}
                      className="hover:underline underline-offset-2"
                      title={`Filter to ${e.admin_username}`}
                    >
                      {e.admin_username}
                    </button>
                  </td>
                  <td className="py-1.5 px-2 font-mono text-accent-400">
                    <button
                      onClick={() => setActionFilter(e.action)}
                      className="hover:underline underline-offset-2"
                      title={`Filter to ${e.action}`}
                    >
                      {e.action}
                    </button>
                  </td>
                  <td className="py-1.5 px-2 text-surface-400 max-w-xs truncate" title={e.details}>{e.details}</td>
                  <td className="py-1.5 px-2 font-mono text-surface-500">
                    {e.ip_address ? (
                      <CopyText value={e.ip_address}>{e.ip_address}</CopyText>
                    ) : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
