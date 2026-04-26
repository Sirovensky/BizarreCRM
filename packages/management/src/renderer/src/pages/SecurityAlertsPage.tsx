import { useCallback, useEffect, useMemo, useState } from 'react';
import { Shield, RefreshCw, CheckCircle2, CheckCheck, AlertTriangle, Info } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { SecurityAlert, SecurityAlertSeverity } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { CopyText } from '@/components/CopyText';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { formatDateTime } from '@/utils/format';
import toast from 'react-hot-toast';
import { formatApiError } from '@/utils/apiError';

type AckFilter = 'unacknowledged' | 'acknowledged' | 'all';

const SEVERITY_COLOR: Record<SecurityAlertSeverity, string> = {
  info: 'text-sky-400 bg-sky-950/40 border-sky-900/50',
  warning: 'text-amber-400 bg-amber-950/40 border-amber-900/50',
  critical: 'text-red-400 bg-red-950/40 border-red-900/50',
};

const SEVERITY_ICON: Record<SecurityAlertSeverity, React.ElementType> = {
  info: Info,
  warning: AlertTriangle,
  critical: AlertTriangle,
};

function prettyDetails(raw: string | null): string {
  if (!raw) return '';
  try {
    const parsed = JSON.parse(raw);
    if (typeof parsed === 'object' && parsed !== null && 'message' in parsed && typeof parsed.message === 'string') {
      return parsed.message;
    }
    return JSON.stringify(parsed);
  } catch {
    return raw;
  }
}

export function SecurityAlertsPage() {
  const [alerts, setAlerts] = useState<SecurityAlert[]>([]);
  const [loading, setLoading] = useState(true);
  const [ackFilter, setAckFilter] = useState<AckFilter>('unacknowledged');
  const [severityFilter, setSeverityFilter] = useState<SecurityAlertSeverity | 'all'>('all');
  const [ackingId, setAckingId] = useState<number | null>(null);
  const [ackingAll, setAckingAll] = useState(false);
  const [expanded, setExpanded] = useState<number | null>(null);
  const [ackAllDialogOpen, setAckAllDialogOpen] = useState(false);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const res = await getAPI().superAdmin.listSecurityAlerts({
        acknowledged: ackFilter === 'all' ? undefined : ackFilter === 'acknowledged' ? 1 : 0,
        severity: severityFilter === 'all' ? undefined : severityFilter,
        limit: 200,
      });
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        setAlerts(res.data.alerts);
      } else {
        toast.error(formatApiError(res));
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to load security alerts');
    } finally {
      setLoading(false);
    }
  }, [ackFilter, severityFilter]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const unackCount = useMemo(
    () => alerts.filter((a) => a.acknowledged === 0).length,
    [alerts]
  );

  async function handleAckOne(id: number) {
    setAckingId(id);
    try {
      const res = await getAPI().superAdmin.acknowledgeAlert(id);
      if (handleApiResponse(res)) return;
      if (res.success) {
        toast.success('Alert acknowledged');
        await refresh();
      } else {
        toast.error(formatApiError(res));
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Acknowledge failed');
    } finally {
      setAckingId(null);
    }
  }

  function handleAckAll() {
    if (unackCount === 0) return;
    // DASH-ELEC-070: replaced window.confirm with ConfirmDialog for consistency.
    setAckAllDialogOpen(true);
  }

  async function doAckAll() {
    setAckAllDialogOpen(false);
    setAckingAll(true);
    try {
      const res = await getAPI().superAdmin.acknowledgeAllAlerts();
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        toast.success(`${res.data.count} alert${res.data.count === 1 ? '' : 's'} acknowledged`);
        await refresh();
      } else {
        toast.error(formatApiError(res));
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Bulk acknowledge failed');
    } finally {
      setAckingAll(false);
    }
  }

  return (
    <div className="space-y-3 lg:space-y-5 animate-fade-in">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
          <Shield className="w-5 h-5 text-accent-400" />
          Security Alerts
          {unackCount > 0 && (
            <span className="text-xs font-medium px-2 py-0.5 rounded-full bg-orange-950/50 text-orange-300 border border-orange-900/60">
              {unackCount} unacknowledged
            </span>
          )}
        </h1>
        <div className="flex items-center gap-2">
          <button
            onClick={handleAckAll}
            disabled={unackCount === 0 || ackingAll}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-emerald-300 bg-emerald-950/40 border border-emerald-900/60 rounded-lg hover:bg-emerald-950/60 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
          >
            <CheckCheck className={`w-3.5 h-3.5 ${ackingAll ? 'animate-pulse' : ''}`} />
            {ackingAll ? 'Acknowledging…' : 'Acknowledge all'}
          </button>
          <button
            onClick={refresh}
            disabled={loading}
            className="p-2 rounded-lg text-surface-400 hover:text-surface-200 hover:bg-surface-800 disabled:opacity-50"
            title="Refresh"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      {/* Filters */}
      <div className="flex items-center gap-2 flex-wrap">
        <div className="flex items-center gap-1 text-xs">
          {(['unacknowledged', 'acknowledged', 'all'] as AckFilter[]).map((f) => (
            <button
              key={f}
              onClick={() => setAckFilter(f)}
              className={`px-2.5 py-1 rounded border transition-colors ${
                ackFilter === f
                  ? 'bg-accent-600/20 border-accent-600 text-accent-300'
                  : 'border-surface-700 text-surface-400 hover:text-surface-200 hover:border-surface-600'
              }`}
            >
              {f[0].toUpperCase() + f.slice(1)}
            </button>
          ))}
        </div>
        <div className="h-4 w-px bg-surface-700" />
        <div className="flex items-center gap-1 text-xs">
          {(['all', 'critical', 'warning', 'info'] as const).map((s) => (
            <button
              key={s}
              onClick={() => setSeverityFilter(s)}
              className={`px-2.5 py-1 rounded border transition-colors ${
                severityFilter === s
                  ? 'bg-accent-600/20 border-accent-600 text-accent-300'
                  : 'border-surface-700 text-surface-400 hover:text-surface-200 hover:border-surface-600'
              }`}
            >
              {s[0].toUpperCase() + s.slice(1)}
            </button>
          ))}
        </div>
      </div>

      {loading && alerts.length === 0 ? (
        <div className="flex items-center justify-center py-20">
          <RefreshCw className="w-5 h-5 text-surface-500 animate-spin" />
        </div>
      ) : alerts.length === 0 ? (
        <div className="text-center py-12 text-sm text-surface-500">
          {ackFilter === 'unacknowledged'
            ? 'No unacknowledged alerts — you are all caught up'
            : 'No alerts match the current filter'}
        </div>
      ) : (
        <div className="space-y-2">
          {alerts.map((alert) => {
            const Icon = SEVERITY_ICON[alert.severity];
            const isOpen = expanded === alert.id;
            const details = prettyDetails(alert.details);
            return (
              <div
                key={alert.id}
                className={`rounded-lg border transition-colors ${
                  alert.acknowledged === 1
                    ? 'bg-surface-900/50 border-surface-800'
                    : 'bg-surface-900 border-surface-700'
                }`}
              >
                {/* DASH-ELEC-065: tabIndex/role/onKeyDown for keyboard accessibility */}
                <div
                  className="flex items-start gap-3 p-3 cursor-pointer focus:outline-none focus:bg-surface-800/30 rounded-t-lg"
                  onClick={() => setExpanded(isOpen ? null : alert.id)}
                  tabIndex={0}
                  role="button"
                  aria-expanded={isOpen}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault();
                      setExpanded(isOpen ? null : alert.id);
                    }
                  }}
                >
                  <div className={`shrink-0 rounded-md border px-2 py-0.5 text-xs font-medium flex items-center gap-1 ${SEVERITY_COLOR[alert.severity]}`}>
                    <Icon className="w-3 h-3" />
                    {alert.severity}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-mono text-sm text-surface-200">{alert.type}</span>
                      {alert.tenant_slug && (
                        <span className="text-xs text-surface-500">
                          tenant: <span className="font-mono text-surface-400">{alert.tenant_slug}</span>
                        </span>
                      )}
                      {alert.ip_address && (
                        <span className="text-xs text-surface-500">
                          ip: <CopyText value={alert.ip_address} className="font-mono text-surface-400">{alert.ip_address}</CopyText>
                        </span>
                      )}
                    </div>
                    {details && (
                      <p className={`text-xs mt-1 text-surface-400 ${isOpen ? '' : 'line-clamp-1'}`}>
                        {details}
                      </p>
                    )}
                    <p className="text-[11px] text-surface-400 mt-1">{formatDateTime(alert.created_at)}</p>
                  </div>
                  <div className="shrink-0">
                    {alert.acknowledged === 1 ? (
                      <span className="inline-flex items-center gap-1 text-xs text-emerald-500/80">
                        <CheckCircle2 className="w-3.5 h-3.5" />
                        acknowledged
                      </span>
                    ) : (
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleAckOne(alert.id);
                        }}
                        disabled={ackingId === alert.id}
                        className="inline-flex items-center gap-1 px-2 py-1 text-xs text-emerald-300 bg-emerald-950/40 border border-emerald-900/60 rounded hover:bg-emerald-950/60 disabled:opacity-50"
                      >
                        <CheckCircle2 className={`w-3 h-3 ${ackingId === alert.id ? 'animate-pulse' : ''}`} />
                        {ackingId === alert.id ? 'Acking…' : 'Acknowledge'}
                      </button>
                    )}
                  </div>
                </div>
                {isOpen && alert.details && (
                  <div className="px-3 pb-3">
                    <pre className="text-[11px] text-surface-400 bg-surface-950 border border-surface-800 rounded p-2 overflow-x-auto whitespace-pre-wrap break-all">
                      {(() => {
                        try {
                          return JSON.stringify(JSON.parse(alert.details!), null, 2);
                        } catch {
                          return alert.details;
                        }
                      })()}
                    </pre>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* DASH-ELEC-070: ConfirmDialog replaces window.confirm for "Acknowledge all" */}
      <ConfirmDialog
        open={ackAllDialogOpen}
        title="Acknowledge all alerts"
        message={`Mark all ${unackCount} unacknowledged alert${unackCount > 1 ? 's' : ''} as reviewed? Review the list before confirming — this cannot be undone.`}
        confirmLabel="Acknowledge all"
        onConfirm={doAckAll}
        onCancel={() => setAckAllDialogOpen(false)}
      />
    </div>
  );
}
