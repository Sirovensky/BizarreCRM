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

interface NavItem {
  to: string;
  icon: React.ElementType;
  label: string;
  multiTenantOnly?: boolean;
}

const NAV_ITEMS: NavItem[] = [
  { to: '/', icon: LayoutDashboard, label: 'Overview' },
  { to: '/tenants', icon: Users, label: 'Tenants', multiTenantOnly: true },
  { to: '/server', icon: Power, label: 'Server Control' },
  { to: '/backups', icon: Database, label: 'Backups' },
  { to: '/crashes', icon: AlertTriangle, label: 'Crash Monitor' },
  { to: '/updates', icon: Download, label: 'Updates' },
  { to: '/activity', icon: Activity, label: 'Activity', multiTenantOnly: true },
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

  const filteredItems = NAV_ITEMS.filter(
    (item) => !item.multiTenantOnly || isMultiTenant
  );

  return (
    <aside
      className={cn(
        'flex flex-col border-r border-surface-800 bg-surface-950 transition-[width] duration-200',
        collapsed ? 'w-[var(--sidebar-collapsed-width)]' : 'w-[var(--sidebar-width)]'
      )}
    >
      {/* Nav items */}
      <nav className="flex-1 py-3 px-2 space-y-0.5 overflow-y-auto">
        {filteredItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.to === '/'}
            className={({ isActive }) =>
              cn(
                'flex items-center gap-3 px-3 py-2 rounded-md text-sm transition-colors',
                isActive
                  ? 'bg-accent-600/15 text-accent-400 font-medium'
                  : 'text-surface-400 hover:text-surface-200 hover:bg-surface-800/60'
              )
            }
            title={collapsed ? item.label : undefined}
          >
            <item.icon className="w-4 h-4 flex-shrink-0" />
            {!collapsed && <span>{item.label}</span>}
          </NavLink>
        ))}
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
