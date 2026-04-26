import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Activity, Shield, ScrollText, ChevronRight, AlertTriangle } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { SecurityAlert } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { formatDateTime } from '@/utils/format';
import { useServerStore } from '@/stores/serverStore';
import { cn } from '@/utils/cn';

// DASH-ELEC-151 (Fixer-C25 2026-04-25): Tailwind-purge-safe explicit color
// map. Keys matched to SecurityAlert.severity union; unknown values fall
// back to the warning amber tone. Static class-name strings live here so
// the JIT scanner picks them all up at build time.
const SEVERITY_COLOR: Record<string, string> = {
  critical: 'text-red-400',
  warning: 'text-amber-400',
  info: 'text-sky-400',
};

interface AuditEntry {
  id: number;
  admin_username: string;
  action: string;
  details: string;
  ip_address: string;
  created_at: string;
}

/**
 * Compact Overview card: last 3 audit entries + last 3 unacknowledged security
 * alerts. Read-only preview — clicking either half jumps to the full Activity
 * page on the matching tab. Single component so the Overview grid layout sees
 * one block and the internal split is a render-detail. Refreshes on mount
 * only — operators who want a live stream go to the dedicated page.
 *
 * Gated on multi-tenant because the endpoints are super-admin only. Single-
 * tenant installs have no master audit log to render.
 */
export function RecentActivityWidget() {
  const stats = useServerStore((s) => s.stats);
  const isMultiTenant = stats?.multiTenant ?? false;

  const [audit, setAudit] = useState<AuditEntry[]>([]);
  const [alerts, setAlerts] = useState<SecurityAlert[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!isMultiTenant) { setLoading(false); return; }
    let cancelled = false;
    Promise.all([
      getAPI().superAdmin.getAuditLog({ limit: 5 }),
      getAPI().superAdmin.listSecurityAlerts({ acknowledged: 0, limit: 3 }),
    ])
      .then(([auditRes, alertsRes]) => {
        if (cancelled) return;
        if (handleApiResponse(auditRes) || handleApiResponse(alertsRes)) return;
        if (auditRes.success && auditRes.data) {
          const list = Array.isArray(auditRes.data)
            ? (auditRes.data as AuditEntry[])
            : ((auditRes.data as { logs?: AuditEntry[] }).logs ?? []);
          setAudit(list.slice(0, 3));
        }
        if (alertsRes.success && alertsRes.data) {
          setAlerts(alertsRes.data.alerts.slice(0, 3));
        }
      })
      .catch((err) => console.warn('[RecentActivity] fetch failed', err))
      .finally(() => !cancelled && setLoading(false));
    return () => { cancelled = true; };
  }, [isMultiTenant]);

  if (!isMultiTenant) return null;

  return (
    <div className="rounded-lg border border-surface-800 bg-surface-900/60 p-3 lg:p-4">
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-sm font-semibold text-surface-200 flex items-center gap-2">
          <Activity className="w-4 h-4 text-accent-400" />
          Recent Activity
        </h2>
        <Link
          to="/activity"
          className="text-[11px] text-surface-500 hover:text-accent-300 inline-flex items-center gap-0.5"
        >
          open full page <ChevronRight className="w-3 h-3" />
        </Link>
      </div>

      {loading ? (
        <p className="text-xs text-surface-500" aria-live="polite" aria-busy="true">Loading…</p>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {/* Audit */}
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <span className="text-[11px] uppercase tracking-wider text-surface-500 flex items-center gap-1.5">
                <ScrollText className="w-3 h-3" />
                Audit log
              </span>
              <Link to="/activity?tab=audit" className="text-[10px] text-surface-500 hover:text-accent-300">
                all →
              </Link>
            </div>
            {audit.length === 0 ? (
              <p className="text-xs text-surface-600">No audit log entries. System will record admin actions here when they occur.</p>
            ) : (
              <ul className="space-y-1.5">
                {audit.map((e) => (
                  <li key={e.id} className="text-[11px] leading-tight">
                    <div className="flex items-center gap-1.5 flex-wrap">
                      <span className="font-mono text-accent-400">{e.action}</span>
                      <span className="text-surface-400">{e.admin_username}</span>
                    </div>
                    <span className="text-[10px] text-surface-600">{formatDateTime(e.created_at)}</span>
                  </li>
                ))}
              </ul>
            )}
          </div>

          {/* Alerts */}
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <span className="text-[11px] uppercase tracking-wider text-surface-500 flex items-center gap-1.5">
                <Shield className="w-3 h-3" />
                Open alerts
              </span>
              <Link to="/activity?tab=alerts" className="text-[10px] text-surface-500 hover:text-accent-300">
                all →
              </Link>
            </div>
            {alerts.length === 0 ? (
              <p className="text-xs text-emerald-400/70">All clear.</p>
            ) : (
              <ul className="space-y-1.5">
                {alerts.map((a) => (
                  <li key={a.id} className="text-[11px] leading-tight">
                    <div className="flex items-center gap-1.5 flex-wrap">
                      <AlertTriangle className={cn('w-3 h-3', SEVERITY_COLOR[a.severity] ?? SEVERITY_COLOR.warning)} />
                      <span className="font-mono text-surface-200">{a.type}</span>
                      {a.tenant_slug && <span className="text-surface-500">· {a.tenant_slug}</span>}
                    </div>
                    <span className="text-[10px] text-surface-600">{formatDateTime(a.created_at)}</span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
