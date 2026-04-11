import { useState, useEffect } from 'react';
import { NavLink, useNavigate, useLocation } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { useUiStore } from '@/stores/uiStore';
import { useAuthStore } from '@/stores/authStore';
import { ticketApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import {
  LayoutDashboard,
  Wrench,
  Users,
  Package,
  FileText,
  UserPlus,
  Calendar,
  ClipboardList,
  ShoppingCart,
  BarChart3,
  MessageSquare,
  UserCog,
  Settings,
  ChevronsLeft,
  ChevronsRight,
  ChevronDown,
  ChevronRight,
  Zap,
  Receipt,
  Store,
  ListTodo,
  Kanban,
} from 'lucide-react';

interface NavItem {
  label: string;
  path: string;
  icon: React.ElementType;
  badge?: number;
  adminOnly?: boolean;
}

interface NavSection {
  title: string;
  items: NavItem[];
  adminOnly?: boolean;
}

// @audit-fixed: marked the Admin section as `adminOnly`. Previously every
// technician saw "Employees" and "Reports" in the sidebar even though both
// pages are admin-gated server-side, producing a dead-click → 403 toast.
// The Sidebar component below filters sections + items by `user.role`.
const navSections: NavSection[] = [
  {
    title: 'Main',
    items: [
      { label: 'Dashboard', path: '/', icon: LayoutDashboard },
      { label: 'POS / Check-In', path: '/pos', icon: ShoppingCart },
      { label: 'Tickets', path: '/tickets', icon: Wrench },
      { label: 'Customers', path: '/customers', icon: Users },
    ],
  },
  {
    title: 'Operations',
    items: [
      { label: 'Inventory', path: '/inventory', icon: Package },
      { label: 'Invoices', path: '/invoices', icon: FileText },
      { label: 'Expenses', path: '/expenses', icon: Receipt },
      { label: 'Purchase Orders', path: '/purchase-orders', icon: Package },
    ],
  },
  {
    title: 'Communications',
    items: [
      { label: 'Messages', path: '/communications', icon: MessageSquare },
      { label: 'Leads', path: '/leads', icon: UserPlus },
      { label: 'Pipeline', path: '/pipeline', icon: Kanban },
      { label: 'Calendar', path: '/calendar', icon: Calendar },
      { label: 'Estimates', path: '/estimates', icon: ClipboardList },
    ],
  },
  {
    title: 'Admin',
    adminOnly: true,
    items: [
      { label: 'Employees', path: '/employees', icon: UserCog, adminOnly: true },
      { label: 'Reports', path: '/reports', icon: BarChart3, adminOnly: true },
    ],
  },
];

function SidebarTooltip({ label, show }: { label: string; show: boolean }) {
  if (!show) return null;
  return (
    <div className="pointer-events-none absolute left-full top-1/2 z-50 ml-2 -translate-y-1/2 rounded-md bg-surface-900 px-2.5 py-1.5 text-xs font-medium text-white shadow-lg dark:bg-surface-100 dark:text-surface-900">
      {label}
      <div className="absolute right-full top-1/2 -translate-y-1/2 border-4 border-transparent border-r-surface-900 dark:border-r-surface-100" />
    </div>
  );
}

export function Sidebar() {
  const { sidebarCollapsed, toggleSidebar } = useUiStore();
  // @audit-fixed: filter nav sections + items by role so technicians don't see
  // admin-only links (Employees, Reports, Settings). Server still enforces auth
  // — this just removes the broken-click experience.
  const userRole = useAuthStore((s) => s.user?.role);
  const isAdmin = userRole === 'admin';
  const visibleSections = navSections
    .filter((section) => !section.adminOnly || isAdmin)
    .map((section) => ({
      ...section,
      items: section.items.filter((item) => !item.adminOnly || isAdmin),
    }))
    .filter((section) => section.items.length > 0);

  return (
    <aside
      className={cn(
        'fixed inset-y-0 left-0 z-30 flex flex-col border-r border-surface-200 bg-white transition-all duration-200 dark:border-surface-800 dark:bg-surface-900',
        sidebarCollapsed ? 'w-16' : 'w-64'
      )}
    >
      {/* Logo / App Name */}
      <div
        className={cn(
          'flex h-16 shrink-0 items-center border-b border-surface-200 dark:border-surface-800',
          sidebarCollapsed ? 'justify-center px-2' : 'gap-3 px-5'
        )}
      >
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-brand-500 to-brand-600 shadow-sm">
          <Zap className="h-4.5 w-4.5 text-white" strokeWidth={2.5} />
        </div>
        {!sidebarCollapsed && (
          <span className="truncate text-lg font-bold tracking-tight text-surface-900 dark:text-surface-50">
            Bizarre CRM
          </span>
        )}
      </div>

      {/* Navigation Items */}
      <nav className="flex-1 overflow-y-auto overflow-x-hidden py-3">
        {sidebarCollapsed ? (
          <ul className="flex flex-col gap-0.5 px-2">
            {visibleSections.flatMap((s) => s.items).map((item) => (
              <SidebarItem key={item.path} item={item} collapsed />
            ))}
          </ul>
        ) : (
          <div className="flex flex-col gap-1">
            {visibleSections.map((section) => (
              <SidebarSection key={section.title} section={section} />
            ))}
          </div>
        )}
      </nav>

      {/* Recent Views */}
      <RecentViews collapsed={sidebarCollapsed} />

      {/* My Queue Widget */}
      <MyQueueWidget collapsed={sidebarCollapsed} />

      {/* Bottom Section */}
      <div className="shrink-0 border-t border-surface-200 p-2 dark:border-surface-800">
        {/* Settings — admin only (server enforces /settings writes by role) */}
        {isAdmin && (
          <NavLink
            to="/settings"
            className={({ isActive }) =>
              cn(
                'group relative flex items-center rounded-lg px-3 py-2.5 text-sm font-medium transition-colors',
                isActive
                  ? 'bg-surface-100 text-surface-900 dark:bg-surface-800 dark:text-surface-50'
                  : 'text-surface-500 hover:bg-surface-50 hover:text-surface-700 dark:text-surface-400 dark:hover:bg-surface-800/60 dark:hover:text-surface-200',
                sidebarCollapsed && 'justify-center px-0'
              )
            }
          >
            <Settings className="h-5 w-5 shrink-0" />
            {!sidebarCollapsed && <span className="ml-3 truncate">Settings</span>}
            {sidebarCollapsed && (
              <SidebarTooltipWrapper label="Settings" />
            )}
          </NavLink>
        )}

        {/* Collapse Toggle */}
        <button
          onClick={toggleSidebar}
          className={cn(
            'mt-1 flex w-full items-center rounded-lg px-3 py-2.5 text-sm font-medium text-surface-400 transition-colors hover:bg-surface-50 hover:text-surface-600 dark:text-surface-500 dark:hover:bg-surface-800/60 dark:hover:text-surface-300',
            sidebarCollapsed && 'justify-center px-0'
          )}
          title={sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
        >
          {sidebarCollapsed ? (
            <ChevronsRight className="h-5 w-5 shrink-0" />
          ) : (
            <>
              <ChevronsLeft className="h-5 w-5 shrink-0" />
              <span className="ml-3 truncate">Collapse</span>
            </>
          )}
        </button>
      </div>
    </aside>
  );
}

function RecentViews({ collapsed }: { collapsed: boolean }) {
  const location = useLocation();
  const [items, setItems] = useState<{ type: string; id: number; label: string; path: string }[]>([]);

  useEffect(() => {
    try {
      const stored = JSON.parse(localStorage.getItem('recent_views') || '[]');
      setItems(stored.slice(0, 5));
    } catch { /* ignore */ }
  }, [location.pathname]);

  if (items.length === 0) return null;

  return (
    <div className="shrink-0 border-t border-surface-200 dark:border-surface-800 px-2 py-2">
      {!collapsed && (
        <p className="px-3 py-1 text-[10px] font-semibold uppercase tracking-wider text-surface-400 dark:text-surface-500">
          Recent
        </p>
      )}
      <ul className="space-y-0.5">
        {items.map((item) => (
          <li key={`${item.type}-${item.id}`}>
            <NavLink
              to={item.path}
              className={({ isActive }) =>
                cn(
                  'group relative flex items-center rounded-lg px-3 py-1.5 text-xs font-medium transition-colors',
                  isActive
                    ? 'bg-surface-100 text-surface-900 dark:bg-surface-800 dark:text-surface-50'
                    : 'text-surface-500 hover:bg-surface-50 hover:text-surface-700 dark:text-surface-400 dark:hover:bg-surface-800/60 dark:hover:text-surface-200',
                  collapsed && 'justify-center px-0'
                )
              }
            >
              {!collapsed && (
                <span className="truncate">{item.label}</span>
              )}
              {collapsed && (
                <>
                  <span className="text-[10px]">{item.label.slice(0, 6)}</span>
                  <SidebarTooltipWrapper label={item.label} />
                </>
              )}
            </NavLink>
          </li>
        ))}
      </ul>
    </div>
  );
}

function MyQueueWidget({ collapsed }: { collapsed: boolean }) {
  const navigate = useNavigate();
  const user = useAuthStore((s) => s.user);

  const { data } = useQuery({
    queryKey: ['my-queue', user?.id],
    queryFn: () => ticketApi.myQueue(),
    enabled: !!user,
    refetchInterval: 30_000,
  });

  const queue = data?.data?.data ?? { total: 0, open: 0, waiting_parts: 0, in_progress: 0 };

  if (queue.total === 0) return null;

  return (
    <div className="shrink-0 border-t border-surface-200 dark:border-surface-800 px-2 py-2">
      <button
        onClick={() => navigate('/tickets?assigned_to=me')}
        className={cn(
          'group relative flex w-full items-center rounded-lg px-3 py-2 text-sm transition-colors hover:bg-surface-50 dark:hover:bg-surface-800/60',
          collapsed && 'justify-center px-0'
        )}
        title="My Queue"
      >
        <ListTodo className="h-5 w-5 shrink-0 text-brand-500" />
        {!collapsed && (
          <div className="ml-3 flex-1 text-left">
            <p className="text-xs font-semibold text-surface-700 dark:text-surface-200">My Queue</p>
            <p className="text-[10px] text-surface-500 dark:text-surface-400">
              {queue.open > 0 && <span>{queue.open} open</span>}
              {queue.open > 0 && queue.in_progress > 0 && <span>, </span>}
              {queue.in_progress > 0 && <span>{queue.in_progress} in progress</span>}
              {(queue.open > 0 || queue.in_progress > 0) && queue.waiting_parts > 0 && <span>, </span>}
              {queue.waiting_parts > 0 && <span>{queue.waiting_parts} waiting parts</span>}
            </p>
          </div>
        )}
        {!collapsed && (
          <span className="ml-auto inline-flex h-5 min-w-[20px] items-center justify-center rounded-full bg-brand-100 px-1.5 text-[11px] font-bold text-brand-700 dark:bg-brand-500/20 dark:text-brand-300">
            {queue.total}
          </span>
        )}
        {collapsed && (
          <>
            <span className="absolute right-1 top-1 h-4 min-w-[16px] rounded-full bg-brand-500 px-1 text-[9px] font-bold leading-4 text-white text-center">
              {queue.total}
            </span>
            <SidebarTooltipWrapper label={`My Queue (${queue.total})`} />
          </>
        )}
      </button>
    </div>
  );
}

function SidebarTooltipWrapper({ label }: { label: string }) {
  return (
    <div className="pointer-events-none absolute left-full top-1/2 z-50 ml-2 -translate-y-1/2 rounded-md bg-surface-900 px-2.5 py-1.5 text-xs font-medium text-white opacity-0 shadow-lg transition-opacity group-hover:opacity-100 dark:bg-surface-100 dark:text-surface-900">
      {label}
      <div className="absolute right-full top-1/2 -translate-y-1/2 border-4 border-transparent border-r-surface-900 dark:border-r-surface-100" />
    </div>
  );
}

function SidebarSection({ section }: { section: NavSection }) {
  const [expanded, setExpanded] = useState(true);

  return (
    <div>
      <button
        onClick={() => setExpanded((v) => !v)}
        className="flex w-full items-center gap-1 px-4 py-1.5 text-[10px] font-semibold uppercase tracking-wider text-surface-400 hover:text-surface-600 dark:text-surface-500 dark:hover:text-surface-300"
      >
        {expanded ? <ChevronDown className="h-3 w-3" /> : <ChevronRight className="h-3 w-3" />}
        {section.title}
      </button>
      {expanded && (
        <ul className="flex flex-col gap-0.5 px-2">
          {section.items.map((item) => (
            <SidebarItem key={item.path} item={item} collapsed={false} />
          ))}
        </ul>
      )}
    </div>
  );
}

function SidebarItem({ item, collapsed }: { item: NavItem; collapsed: boolean }) {
  const Icon = item.icon;

  return (
    <li>
      <NavLink
        to={item.path}
        end={item.path === '/'}
        className={({ isActive }) =>
          cn(
            'group relative flex items-center rounded-lg px-3 py-2.5 text-sm font-medium transition-colors',
            isActive
              ? 'bg-brand-50 text-brand-700 dark:bg-brand-500/10 dark:text-brand-400'
              : 'text-surface-600 hover:bg-surface-50 hover:text-surface-900 dark:text-surface-400 dark:hover:bg-surface-800/60 dark:hover:text-surface-100',
            collapsed && 'justify-center px-0'
          )
        }
      >
        {({ isActive }) => (
          <>
            {/* Active indicator bar */}
            {isActive && (
              <div className="absolute inset-y-1 left-0 w-[3px] rounded-full bg-brand-500" />
            )}

            <Icon className={cn('h-5 w-5 shrink-0', isActive && 'text-brand-600 dark:text-brand-400')} />

            {!collapsed && (
              <>
                <span className="ml-3 flex-1 truncate">{item.label}</span>

                {item.badge != null && item.badge > 0 && (
                  <span
                    className={cn(
                      'ml-auto inline-flex h-5 min-w-[20px] items-center justify-center rounded-full px-1.5 text-[11px] font-semibold leading-none',
                      isActive
                        ? 'bg-brand-100 text-brand-700 dark:bg-brand-500/20 dark:text-brand-300'
                        : 'bg-surface-100 text-surface-600 dark:bg-surface-800 dark:text-surface-300'
                    )}
                  >
                    {item.badge}
                  </span>
                )}
              </>
            )}

            {/* Badge dot when collapsed */}
            {collapsed && item.badge != null && item.badge > 0 && (
              <span className="absolute right-1.5 top-1.5 h-2 w-2 rounded-full bg-brand-500" />
            )}

            {/* Tooltip when collapsed */}
            {collapsed && (
              <SidebarTooltipWrapper label={item.label} />
            )}
          </>
        )}
      </NavLink>
    </li>
  );
}
