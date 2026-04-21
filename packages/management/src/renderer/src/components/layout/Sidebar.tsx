import { NavLink } from 'react-router-dom';
import {
  LayoutDashboard,
  Users,
  Database,
  AlertTriangle,
  Power,
  Download,
  Settings,
  Activity,
  Wrench,
  FileText,
  Stethoscope,
  ChevronLeft,
  ChevronRight,
} from 'lucide-react';
import { cn } from '@/utils/cn';
import { useUiStore } from '@/stores/uiStore';
import { useServerStore } from '@/stores/serverStore';

type BadgeKind = 'alerts';

interface NavItem {
  to: string;
  icon: React.ElementType;
  label: string;
  multiTenantOnly?: boolean;
  /** Live-count badge derived from server stats (already in the store). */
  badge?: BadgeKind;
}

const NAV_ITEMS: NavItem[] = [
  { to: '/', icon: LayoutDashboard, label: 'Overview' },
  { to: '/tenants', icon: Users, label: 'Tenants', multiTenantOnly: true },
  { to: '/server', icon: Power, label: 'Server Control' },
  { to: '/backups', icon: Database, label: 'Backups' },
  { to: '/crashes', icon: AlertTriangle, label: 'Crash Monitor' },
  { to: '/updates', icon: Download, label: 'Updates' },
  { to: '/activity', icon: Activity, label: 'Activity', multiTenantOnly: true, badge: 'alerts' },
  { to: '/logs', icon: FileText, label: 'Server Logs' },
  { to: '/diagnostics', icon: Stethoscope, label: 'Diagnostics', multiTenantOnly: true },
  { to: '/tools', icon: Wrench, label: 'Admin Tools', multiTenantOnly: true },
  { to: '/settings', icon: Settings, label: 'Settings' },
];

export function Sidebar() {
  const collapsed = useUiStore((s) => s.sidebarCollapsed);
  const toggle = useUiStore((s) => s.toggleSidebar);
  const stats = useServerStore((s) => s.stats);
  const isMultiTenant = stats?.multiTenant ?? false;
  const unackAlerts = stats?.unacknowledgedSecurityAlerts ?? 0;

  const filteredItems = NAV_ITEMS.filter(
    (item) => !item.multiTenantOnly || isMultiTenant
  );

  function badgeCount(kind: BadgeKind): number {
    if (kind === 'alerts') return unackAlerts;
    return 0;
  }

  return (
    <aside
      className={cn(
        'flex flex-col border-r border-surface-800 bg-surface-950 transition-[width] duration-200',
        collapsed ? 'w-[var(--sidebar-collapsed-width)]' : 'w-[var(--sidebar-width)]'
      )}
    >
      {/* Nav items */}
      <nav className="flex-1 py-3 px-2 space-y-0.5 overflow-y-auto">
        {filteredItems.map((item) => {
          const count = item.badge ? badgeCount(item.badge) : 0;
          return (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.to === '/'}
              className={({ isActive }) =>
                cn(
                  'relative flex items-center gap-3 px-3 py-2 rounded-md text-sm transition-colors',
                  isActive
                    ? 'bg-accent-600/15 text-accent-400 font-medium'
                    : 'text-surface-400 hover:text-surface-200 hover:bg-surface-800/60'
                )
              }
              title={collapsed ? `${item.label}${count > 0 ? ` (${count})` : ''}` : undefined}
            >
              <span className="relative flex-shrink-0">
                <item.icon className="w-4 h-4" />
                {/* Red dot overlay when collapsed — expanded state uses a
                    pill next to the label instead so the count is readable. */}
                {collapsed && count > 0 && (
                  <span className="absolute -top-1 -right-1 w-2 h-2 rounded-full bg-orange-500 ring-1 ring-surface-950" />
                )}
              </span>
              {!collapsed && (
                <>
                  <span className="flex-1">{item.label}</span>
                  {count > 0 && (
                    <span className="text-[10px] font-medium px-1.5 py-0.5 rounded-full bg-orange-950/60 text-orange-300 border border-orange-900/60">
                      {count}
                    </span>
                  )}
                </>
              )}
            </NavLink>
          );
        })}
      </nav>

      {/* Collapse toggle */}
      <button
        onClick={toggle}
        className="flex items-center justify-center py-3 border-t border-surface-800 text-surface-500 hover:text-surface-300 hover:bg-surface-800/60 transition-colors"
        title={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
      >
        {collapsed ? (
          <ChevronRight className="w-4 h-4" />
        ) : (
          <ChevronLeft className="w-4 h-4" />
        )}
      </button>
    </aside>
  );
}
