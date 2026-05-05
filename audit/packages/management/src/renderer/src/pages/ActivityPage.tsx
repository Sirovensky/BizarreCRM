import { useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Activity, ScrollText, Shield, KeyRound, UserCheck } from 'lucide-react';
import { AuditLogPage } from '@/pages/AuditLogPage';
import { SecurityAlertsPage } from '@/pages/SecurityAlertsPage';
import { SessionsPage } from '@/pages/SessionsPage';
import { TenantAuthEventsPanel } from '@/pages/activity/TenantAuthEventsPanel';
import { useServerStore } from '@/stores/serverStore';

type TabId = 'alerts' | 'audit' | 'sessions' | 'tenant-auth';

interface TabDef {
  id: TabId;
  label: string;
  icon: React.ElementType;
  iconColor: string;
  // Show count badge for unack'd security alerts.
  badge?: 'unack-alerts';
}

const TABS: readonly TabDef[] = [
  { id: 'alerts', label: 'Security Alerts', icon: Shield, iconColor: 'text-orange-400', badge: 'unack-alerts' },
  { id: 'audit', label: 'Audit Log', icon: ScrollText, iconColor: 'text-accent-400' },
  { id: 'sessions', label: 'Sessions', icon: KeyRound, iconColor: 'text-violet-400' },
  { id: 'tenant-auth', label: 'Tenant Auth Events', icon: UserCheck, iconColor: 'text-emerald-400' },
];

function isValidTab(value: string | null): value is TabId {
  return TABS.some((t) => t.id === value);
}

export function ActivityPage() {
  const [params, setParams] = useSearchParams();
  const requested = params.get('tab');
  const active: TabId = isValidTab(requested) ? requested : 'alerts';
  const stats = useServerStore((s) => s.stats);
  const unackCount = stats?.unacknowledgedSecurityAlerts ?? 0;

  // Normalize the URL — if no tab param, set the default so deep-linking works.
  useEffect(() => {
    if (!requested) {
      const next = new URLSearchParams(params);
      next.set('tab', active);
      setParams(next, { replace: true });
    }
  }, [requested, active, params, setParams]);

  function setTab(id: TabId) {
    const next = new URLSearchParams(params);
    next.set('tab', id);
    setParams(next, { replace: true });
  }

  return (
    <div className="space-y-4 animate-fade-in flex flex-col h-full">
      <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
        <Activity className="w-5 h-5 text-accent-400" />
        Activity
      </h1>

      <div role="tablist" aria-label="Activity sections" className="flex items-center gap-1 border-b border-surface-800 -mt-2">
        {TABS.map((tab) => {
          const Icon = tab.icon;
          const isActive = active === tab.id;
          const showBadge = tab.badge === 'unack-alerts' && unackCount > 0;
          return (
            <button
              key={tab.id}
              role="tab"
              aria-selected={isActive}
              aria-controls={`tabpanel-${tab.id}`}
              id={`tab-${tab.id}`}
              onClick={() => setTab(tab.id)}
              className={`flex items-center gap-2 px-3 py-2 text-sm border-b-2 -mb-px transition-colors ${
                isActive
                  ? 'border-accent-500 text-surface-100'
                  : 'border-transparent text-surface-500 hover:text-surface-300'
              }`}
            >
              <Icon className={`w-4 h-4 ${isActive ? tab.iconColor : ''}`} />
              {tab.label}
              {showBadge && (
                <span className="text-[10px] font-medium px-1.5 py-0.5 rounded-full bg-orange-950/60 text-orange-300 border border-orange-900/60">
                  {unackCount}
                </span>
              )}
            </button>
          );
        })}
      </div>

      <div
        role="tabpanel"
        id={`tabpanel-${active}`}
        aria-labelledby={`tab-${active}`}
        className="flex-1 min-h-0"
      >
        {active === 'alerts' && <SecurityAlertsPage />}
        {active === 'audit' && <AuditLogPage />}
        {active === 'sessions' && <SessionsPage />}
        {active === 'tenant-auth' && <TenantAuthEventsPanel />}
      </div>
    </div>
  );
}
