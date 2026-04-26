import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Stethoscope, Send, Webhook, Zap } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { Tenant } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { NotificationsPanel } from '@/pages/diagnostics/NotificationsPanel';
import { WebhookFailuresPanel } from '@/pages/diagnostics/WebhookFailuresPanel';
import { AutomationRunsPanel } from '@/pages/diagnostics/AutomationRunsPanel';

type TabId = 'notifications' | 'webhooks' | 'automations';

const TABS: Array<{ id: TabId; label: string; icon: React.ElementType; iconColor: string }> = [
  { id: 'notifications', label: 'Notifications', icon: Send, iconColor: 'text-sky-400' },
  { id: 'webhooks', label: 'Webhook Failures', icon: Webhook, iconColor: 'text-red-400' },
  { id: 'automations', label: 'Automation Runs', icon: Zap, iconColor: 'text-amber-400' },
];

function isValidTab(v: string | null): v is TabId {
  return TABS.some((t) => t.id === v);
}

export function DiagnosticsPage() {
  const [tenants, setTenants] = useState<Tenant[]>([]);
  const [tenantsLoading, setTenantsLoading] = useState(true);
  const [selectedSlug, setSelectedSlug] = useState<string>('');
  const [params, setParams] = useSearchParams();
  const requested = params.get('tab');
  const active: TabId = isValidTab(requested) ? requested : 'notifications';

  useEffect(() => {
    if (!requested) {
      const next = new URLSearchParams(params);
      next.set('tab', active);
      setParams(next, { replace: true });
    }
  }, [requested, active, params, setParams]);

  useEffect(() => {
    let cancelled = false;
    getAPI().superAdmin.listTenants()
      .then((res) => {
        if (cancelled) return;
        if (handleApiResponse(res)) return;
        if (res.success && res.data) {
          setTenants(res.data.tenants);
          const first = res.data.tenants.find((t) => t.status === 'active') ?? res.data.tenants[0];
          if (first) setSelectedSlug(first.slug);
        }
      })
      .catch((err) => console.warn('[Diagnostics] listTenants failed', err))
      .finally(() => !cancelled && setTenantsLoading(false));
    return () => { cancelled = true; };
  }, []);

  function setTab(id: TabId) {
    const next = new URLSearchParams(params);
    next.set('tab', id);
    setParams(next, { replace: true });
  }

  return (
    <div className="space-y-3 lg:space-y-4 animate-fade-in flex flex-col h-full">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <h1 className="text-base lg:text-lg font-bold text-surface-100 flex items-center gap-2">
          <Stethoscope className="w-5 h-5 text-accent-400" />
          Tenant Diagnostics
        </h1>
        {!tenantsLoading && tenants.length > 0 && (
          <select
            value={selectedSlug}
            onChange={(e) => setSelectedSlug(e.target.value)}
            className="px-2 py-1 text-xs bg-surface-950 border border-surface-700 rounded text-surface-200 font-mono"
          >
            {tenants.map((t) => (
              <option key={t.slug} value={t.slug}>
                {t.slug} {t.status !== 'active' ? `(${t.status})` : ''}
              </option>
            ))}
          </select>
        )}
      </div>

      {/* Tabs — DASH-ELEC-066: role="tablist"/role="tab"/aria-selected/aria-controls */}
      <div
        role="tablist"
        aria-label="Diagnostics sections"
        className="flex items-center gap-1 border-b border-surface-800 -mt-1"
      >
        {TABS.map((tab) => {
          const Icon = tab.icon;
          const isActive = active === tab.id;
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
            </button>
          );
        })}
      </div>

      {tenantsLoading ? (
        <p className="text-xs text-surface-500">Loading tenants…</p>
      ) : tenants.length === 0 ? (
        <p className="text-xs text-surface-500">No tenants found</p>
      ) : !selectedSlug ? (
        <p className="text-xs text-surface-500">Select a tenant above to start diagnosing.</p>
      ) : (
        // DASH-ELEC-074 (Fixer-C24 2026-04-25): keep all three panels mounted
        // and toggle visibility via `hidden` so flipping tabs doesn't unmount
        // the active panel (which previously caused a flash of empty state +
        // re-fetch). aria-labelledby is set per panel; hidden=true short-
        // circuits screen readers from announcing inactive panels.
        <div className="flex-1 min-h-0">
          <div
            role="tabpanel"
            id="tabpanel-notifications"
            aria-labelledby="tab-notifications"
            hidden={active !== 'notifications'}
            className={active === 'notifications' ? 'h-full' : ''}
          >
            <NotificationsPanel slug={selectedSlug} />
          </div>
          <div
            role="tabpanel"
            id="tabpanel-webhooks"
            aria-labelledby="tab-webhooks"
            hidden={active !== 'webhooks'}
            className={active === 'webhooks' ? 'h-full' : ''}
          >
            <WebhookFailuresPanel slug={selectedSlug} />
          </div>
          <div
            role="tabpanel"
            id="tabpanel-automations"
            aria-labelledby="tab-automations"
            hidden={active !== 'automations'}
            className={active === 'automations' ? 'h-full' : ''}
          >
            <AutomationRunsPanel slug={selectedSlug} />
          </div>
        </div>
      )}
    </div>
  );
}
