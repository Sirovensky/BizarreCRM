import { useState, useEffect, useCallback } from 'react';
import { ScrollText, RefreshCw } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { formatDateTime } from '@/utils/format';
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

  const refresh = useCallback(async () => {
    try {
      // AUDIT-MGT-008: pass typed object; query string is built in main process.
      const res = await getAPI().superAdmin.getAuditLog({ limit: 100 });
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
  }, []);

  useEffect(() => { refresh(); }, [refresh]);

  if (loading) {
    return <div className="flex items-center justify-center py-20"><RefreshCw className="w-5 h-5 text-surface-500 animate-spin" /></div>;
  }

  return (
    <div className="space-y-3 lg:space-y-5 animate-fade-in">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
          <ScrollText className="w-5 h-5 text-accent-400" />
          Audit Log
        </h1>
        <button onClick={refresh} className="p-2 rounded-lg text-surface-400 hover:text-surface-200 hover:bg-surface-800">
          <RefreshCw className="w-4 h-4" />
        </button>
      </div>

      {entries.length === 0 ? (
        <div className="text-center py-12 text-sm text-surface-500">No audit entries found</div>
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
              {entries.map((e) => (
                <tr key={e.id} className="border-b border-surface-800/50 hover:bg-surface-800/30">
                  <td className="py-2 px-3 text-surface-500 whitespace-nowrap">{formatDateTime(e.created_at)}</td>
                  <td className="py-2 px-3 text-surface-300 font-medium">{e.admin_username}</td>
                  <td className="py-2 px-3 font-mono text-accent-400">{e.action}</td>
                  <td className="py-2 px-3 text-surface-400 max-w-xs truncate" title={e.details}>{e.details}</td>
                  <td className="py-2 px-3 font-mono text-surface-500">{e.ip_address}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
