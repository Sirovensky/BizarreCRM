import { useCallback, useEffect, useState } from 'react';
import { UserCheck, RefreshCw, Filter } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { CopyText } from '@/components/CopyText';
import { formatDateTime } from '@/utils/format';
import toast from 'react-hot-toast';

interface AuthEvent {
  id: number;
  tenant_slug: string;
  event: string;
  ip_address: string;
  user_agent?: string;
  details?: string;
  created_at: string;
}

const EVENT_PRESETS = ['', 'login_success', 'login_failure', 'totp_failure', 'password_reset', 'pin_failure'] as const;

export function TenantAuthEventsPanel() {
  const [events, setEvents] = useState<AuthEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [tenantFilter, setTenantFilter] = useState('');
  const [ipFilter, setIpFilter] = useState('');
  const [eventFilter, setEventFilter] = useState('');

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const params: Record<string, string | number> = { limit: 100 };
      if (tenantFilter) params.tenant_slug = tenantFilter;
      if (ipFilter) params.ip = ipFilter;
      if (eventFilter) params.event = eventFilter;
      const res = await getAPI().superAdmin.listTenantAuthEvents(params);
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        setEvents(res.data.events);
      } else if (res.message) {
        toast.error(res.message);
        setEvents([]);
      }
    } catch (err) {
      console.warn('[TenantAuthEvents] failed', err);
      setEvents([]);
    } finally {
      setLoading(false);
    }
  }, [tenantFilter, ipFilter, eventFilter]);

  useEffect(() => { refresh(); }, [refresh]);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <h2 className="text-base font-semibold text-surface-200 flex items-center gap-2">
          <UserCheck className="w-4 h-4 text-emerald-400" />
          Tenant Auth Events
        </h2>
        <button
          onClick={refresh}
          disabled={loading}
          className="p-2 rounded text-surface-400 hover:text-surface-200 hover:bg-surface-800 disabled:opacity-50"
          title="Refresh"
        >
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </div>

      <div className="flex items-center gap-2 flex-wrap text-xs">
        <Filter className="w-3.5 h-3.5 text-surface-500" />
        <input
          type="text"
          placeholder="tenant slug"
          value={tenantFilter}
          onChange={(e) => setTenantFilter(e.target.value.toLowerCase().trim())}
          className="px-2 py-1 bg-surface-950 border border-surface-700 rounded text-surface-200 placeholder:text-surface-600 font-mono w-40"
        />
        <input
          type="text"
          placeholder="IP address"
          value={ipFilter}
          onChange={(e) => setIpFilter(e.target.value.trim())}
          className="px-2 py-1 bg-surface-950 border border-surface-700 rounded text-surface-200 placeholder:text-surface-600 font-mono w-36"
        />
        <select
          value={eventFilter}
          onChange={(e) => setEventFilter(e.target.value)}
          className="px-2 py-1 bg-surface-950 border border-surface-700 rounded text-surface-200"
        >
          {EVENT_PRESETS.map((e) => <option key={e} value={e}>{e || 'any event'}</option>)}
        </select>
        {(tenantFilter || ipFilter || eventFilter) && (
          <button
            onClick={() => { setTenantFilter(''); setIpFilter(''); setEventFilter(''); }}
            className="text-surface-500 hover:text-surface-300 px-2"
          >
            clear
          </button>
        )}
      </div>

      {events.length === 0 ? (
        <div className="text-center py-12 text-sm text-surface-500">
          {loading ? 'Loading…' : 'No tenant auth events match the current filter.'}
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-surface-800">
                <th className="text-left py-2 px-3 text-surface-500 font-medium">Time</th>
                <th className="text-left py-2 px-3 text-surface-500 font-medium">Tenant</th>
                <th className="text-left py-2 px-3 text-surface-500 font-medium">Event</th>
                <th className="text-left py-2 px-3 text-surface-500 font-medium">IP</th>
                <th className="text-left py-2 px-3 text-surface-500 font-medium">User-Agent</th>
              </tr>
            </thead>
            <tbody>
              {events.map((e) => (
                <tr key={e.id} className="border-b border-surface-800/50 hover:bg-surface-800/30">
                  <td className="py-2 px-3 text-surface-500 whitespace-nowrap">{formatDateTime(e.created_at)}</td>
                  <td className="py-2 px-3 text-surface-300 font-mono">{e.tenant_slug}</td>
                  <td className={`py-2 px-3 font-mono ${e.event.includes('failure') ? 'text-red-400' : 'text-emerald-400'}`}>
                    {e.event}
                  </td>
                  <td className="py-2 px-3 font-mono text-surface-500">
                    {e.ip_address ? <CopyText value={e.ip_address}>{e.ip_address}</CopyText> : '—'}
                  </td>
                  <td className="py-2 px-3 text-surface-500 max-w-xs truncate" title={e.user_agent ?? ''}>
                    {e.user_agent ?? '—'}
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
