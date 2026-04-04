import { useState, useRef, useEffect, useCallback, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { useUiStore } from '@/stores/uiStore';
import { useAuthStore } from '@/stores/authStore';
import { notificationApi, smsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import {
  Search,
  Sun,
  Moon,
  Monitor,
  Bell,
  ChevronDown,
  User,
  Settings,
  ArrowLeftRight,
  LogOut,
  CheckCheck,
  Ticket,
  FileText,
  Package,
  MessageSquare,
  Info,
} from 'lucide-react';

interface Notification {
  id: number;
  type: string;
  message: string;
  entity_type?: string;
  entity_id?: number;
  is_read: number;
  created_at: string;
}

export function Header({ hamburgerButton }: { hamburgerButton?: React.ReactNode }) {
  const navigate = useNavigate();
  const { theme, setTheme, setCommandPaletteOpen } = useUiStore();
  const { user, logout } = useAuthStore();

  const isMac = useMemo(() => /Mac|iPhone|iPad|iPod/.test(navigator.platform || navigator.userAgent), []);
  const shortcutLabel = isMac ? '\u2318K' : 'Ctrl+K';

  const [userMenuOpen, setUserMenuOpen] = useState(false);
  const [themeMenuOpen, setThemeMenuOpen] = useState(false);
  const [notifOpen, setNotifOpen] = useState(false);
  const [unreadCount, setUnreadCount] = useState(0);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [notifLoading, setNotifLoading] = useState(false);
  const [smsUnreadCount, setSmsUnreadCount] = useState(0);

  const userMenuRef = useRef<HTMLDivElement>(null);
  const themeMenuRef = useRef<HTMLDivElement>(null);
  const notifRef = useRef<HTMLDivElement>(null);

  // Fetch unread count on mount + poll every 30s
  const fetchUnreadCount = useCallback(async () => {
    try {
      const res = await notificationApi.unreadCount();
      setUnreadCount(res.data?.data?.count ?? 0);
    } catch {
      // silently fail
    }
  }, []);

  const fetchSmsUnreadCount = useCallback(async () => {
    try {
      const res = await smsApi.conversations();
      const convos = (res.data as any)?.data?.conversations ?? [];
      const total = convos.reduce((sum: number, c: any) => sum + (c.unread_count ?? 0), 0);
      setSmsUnreadCount(total);
    } catch {
      // silently fail
    }
  }, []);

  useEffect(() => {
    fetchUnreadCount();
    fetchSmsUnreadCount();
    const interval = setInterval(() => { fetchUnreadCount(); fetchSmsUnreadCount(); }, 30_000);
    return () => clearInterval(interval);
  }, [fetchUnreadCount, fetchSmsUnreadCount]);

  // Fetch notifications when dropdown opens
  const fetchNotifications = useCallback(async () => {
    setNotifLoading(true);
    try {
      const res = await notificationApi.list({ pagesize: 10 });
      setNotifications(res.data?.data?.notifications ?? []);
    } catch {
      // silently fail
    } finally {
      setNotifLoading(false);
    }
  }, []);

  const handleBellClick = useCallback(() => {
    const opening = !notifOpen;
    setNotifOpen(opening);
    if (opening) fetchNotifications();
  }, [notifOpen, fetchNotifications]);

  const handleMarkAllRead = useCallback(async () => {
    try {
      await notificationApi.markAllRead();
      setUnreadCount(0);
      setNotifications((prev) => prev.map((n) => ({ ...n, is_read: 1 })));
    } catch {
      // silently fail
    }
  }, []);

  const handleNotifClick = useCallback(async (notif: Notification) => {
    // Mark as read
    if (!notif.is_read) {
      try {
        await notificationApi.markRead(notif.id);
        setUnreadCount((c) => Math.max(0, c - 1));
        setNotifications((prev) =>
          prev.map((n) => (n.id === notif.id ? { ...n, is_read: 1 } : n))
        );
      } catch {
        // silently fail
      }
    }
    // Navigate to entity
    if (notif.entity_type && notif.entity_id) {
      const routes: Record<string, string> = {
        ticket: '/tickets',
        invoice: '/invoices',
        customer: '/customers',
        inventory: '/inventory',
        lead: '/leads',
      };
      const base = routes[notif.entity_type];
      if (base) navigate(`${base}/${notif.entity_id}`);
    }
    setNotifOpen(false);
  }, [navigate]);

  // Close menus on outside click
  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (userMenuRef.current && !userMenuRef.current.contains(e.target as Node)) {
        setUserMenuOpen(false);
      }
      if (themeMenuRef.current && !themeMenuRef.current.contains(e.target as Node)) {
        setThemeMenuOpen(false);
      }
      if (notifRef.current && !notifRef.current.contains(e.target as Node)) {
        setNotifOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Cmd+K / Ctrl+K shortcut
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        setCommandPaletteOpen(true);
      }
    },
    [setCommandPaletteOpen]
  );

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);

  const currentThemeIcon =
    theme === 'dark' ? <Moon className="h-4.5 w-4.5" /> :
    theme === 'light' ? <Sun className="h-4.5 w-4.5" /> :
    <Monitor className="h-4.5 w-4.5" />;

  const initials = user
    ? `${user.first_name?.[0] ?? ''}${user.last_name?.[0] ?? ''}`.toUpperCase() || '?'
    : '?';

  return (
    <header className="relative z-30 flex h-16 shrink-0 items-center gap-4 border-b border-surface-200 bg-white/80 px-4 sm:px-6 backdrop-blur-sm dark:border-surface-800 dark:bg-surface-900/80">
      {/* Left: Hamburger (mobile) + Breadcrumb area (placeholder) */}
      <div className="flex flex-1 items-center gap-2">
        {hamburgerButton}
      </div>

      {/* Center: Search */}
      <button
        onClick={() => setCommandPaletteOpen(true)}
        className="flex h-9 w-full max-w-md items-center gap-2 rounded-lg border border-surface-200 bg-surface-50 px-3 text-sm text-surface-400 transition-colors hover:border-surface-300 hover:bg-surface-100 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-500 dark:hover:border-surface-600 dark:hover:bg-surface-750"
      >
        <Search className="h-4 w-4 shrink-0" />
        <span className="flex-1 text-left">Search or press {shortcutLabel}...</span>
        <kbd className="hidden rounded border border-surface-200 bg-white px-1.5 py-0.5 text-[11px] font-medium text-surface-400 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-400 sm:inline-block">
          {shortcutLabel}
        </kbd>
      </button>

      {/* Right: Actions */}
      <div className="flex flex-1 items-center justify-end gap-1">
        {/* Theme Toggle */}
        <div ref={themeMenuRef} className="relative">
          <button
            onClick={() => setThemeMenuOpen((o) => !o)}
            className="flex h-9 w-9 items-center justify-center rounded-lg text-surface-500 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-200"
            title="Toggle theme"
            aria-label="Toggle theme"
          >
            {currentThemeIcon}
          </button>

          {themeMenuOpen && (
            <div className="absolute right-0 top-full z-50 mt-1.5 w-36 overflow-hidden rounded-xl border border-surface-200 bg-white p-1 shadow-lg dark:border-surface-700 dark:bg-surface-800">
              <ThemeOption
                icon={<Sun className="h-4 w-4" />}
                label="Light"
                active={theme === 'light'}
                onClick={() => { setTheme('light'); setThemeMenuOpen(false); }}
              />
              <ThemeOption
                icon={<Moon className="h-4 w-4" />}
                label="Dark"
                active={theme === 'dark'}
                onClick={() => { setTheme('dark'); setThemeMenuOpen(false); }}
              />
              <ThemeOption
                icon={<Monitor className="h-4 w-4" />}
                label="System"
                active={theme === 'system'}
                onClick={() => { setTheme('system'); setThemeMenuOpen(false); }}
              />
            </div>
          )}
        </div>

        {/* SMS quick-access */}
        <button
          onClick={() => navigate('/communications')}
          className="relative flex h-9 w-9 items-center justify-center rounded-lg text-surface-500 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-200"
          title="Messages"
          aria-label="Messages"
        >
          <MessageSquare className="h-4.5 w-4.5" />
          {smsUnreadCount > 0 && (
            <span className="absolute -right-0.5 -top-0.5 flex h-4.5 min-w-[18px] items-center justify-center rounded-full bg-green-500 px-1 text-[10px] font-bold leading-none text-white shadow-sm">
              {smsUnreadCount > 99 ? '99+' : smsUnreadCount}
            </span>
          )}
        </button>

        {/* Notifications */}
        <div ref={notifRef} className="relative">
          <button
            onClick={handleBellClick}
            className={cn(
              'relative flex h-9 w-9 items-center justify-center rounded-lg text-surface-500 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-200',
              notifOpen && 'bg-surface-100 dark:bg-surface-800'
            )}
            title="Notifications"
            aria-label="Notifications"
          >
            <Bell className="h-4.5 w-4.5" />
            {unreadCount > 0 && (
              <span className="absolute -right-0.5 -top-0.5 flex h-4.5 min-w-[18px] items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold leading-none text-white shadow-sm">
                {unreadCount > 99 ? '99+' : unreadCount}
              </span>
            )}
          </button>

          {notifOpen && (
            <div className="absolute right-0 top-full z-50 mt-1.5 w-80 overflow-hidden rounded-xl border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
              {/* Header */}
              <div className="flex items-center justify-between border-b border-surface-100 px-4 py-3 dark:border-surface-700">
                <p className="text-sm font-semibold text-surface-800 dark:text-surface-100">
                  Notifications
                </p>
                {unreadCount > 0 && (
                  <button
                    onClick={handleMarkAllRead}
                    className="flex items-center gap-1 text-xs font-medium text-brand-600 transition-colors hover:text-brand-700 dark:text-brand-400 dark:hover:text-brand-300"
                  >
                    <CheckCheck className="h-3.5 w-3.5" />
                    Mark all read
                  </button>
                )}
              </div>

              {/* Notification list */}
              <div className="max-h-[400px] overflow-y-auto">
                {notifLoading && notifications.length === 0 ? (
                  <div className="flex items-center justify-center py-8">
                    <div className="h-5 w-5 animate-spin rounded-full border-2 border-surface-200 border-t-brand-500" />
                  </div>
                ) : notifications.length === 0 ? (
                  <div className="flex flex-col items-center gap-2 py-8 text-center">
                    <Bell className="h-8 w-8 text-surface-200 dark:text-surface-700" />
                    <p className="text-sm text-surface-400 dark:text-surface-500">
                      No notifications yet
                    </p>
                  </div>
                ) : (
                  notifications.map((notif) => (
                    <NotificationItem
                      key={notif.id}
                      notification={notif}
                      onClick={() => handleNotifClick(notif)}
                    />
                  ))
                )}
              </div>
            </div>
          )}
        </div>

        {/* Divider */}
        <div className="mx-1.5 h-6 w-px bg-surface-200 dark:bg-surface-700" />

        {/* User Menu */}
        <div ref={userMenuRef} className="relative">
          <button
            onClick={() => setUserMenuOpen((o) => !o)}
            className={cn(
              'flex items-center gap-2 rounded-lg px-2 py-1.5 transition-colors hover:bg-surface-100 dark:hover:bg-surface-800',
              userMenuOpen && 'bg-surface-100 dark:bg-surface-800'
            )}
            aria-label="User menu"
          >
            <div className="flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-brand-400 to-brand-600 text-xs font-bold text-white shadow-sm">
              {initials}
            </div>
            <div className="hidden text-left md:block">
              <p className="text-sm font-medium leading-tight text-surface-800 dark:text-surface-100">
                {user ? `${user.first_name} ${user.last_name}` : 'User'}
              </p>
              <p className="text-xs leading-tight text-surface-400 dark:text-surface-500">
                {user?.role ?? 'Unknown'}
              </p>
            </div>
            <ChevronDown
              className={cn(
                'hidden h-4 w-4 text-surface-400 transition-transform md:block',
                userMenuOpen && 'rotate-180'
              )}
            />
          </button>

          {userMenuOpen && (
            <div className="absolute right-0 top-full z-50 mt-1.5 w-56 overflow-hidden rounded-xl border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
              {/* User Info */}
              <div className="border-b border-surface-100 px-4 py-3 dark:border-surface-700">
                <p className="text-sm font-semibold text-surface-800 dark:text-surface-100">
                  {user ? `${user.first_name} ${user.last_name}` : 'User'}
                </p>
                <p className="text-xs text-surface-400 dark:text-surface-500">
                  {user?.email ?? ''}
                </p>
              </div>

              {/* Menu Items */}
              <div className="p-1">
                <DropdownItem
                  icon={<User className="h-4 w-4" />}
                  label="Profile"
                  onClick={() => { setUserMenuOpen(false); navigate('/settings/users'); }}
                />
                <DropdownItem
                  icon={<Settings className="h-4 w-4" />}
                  label="Settings"
                  onClick={() => { setUserMenuOpen(false); navigate('/settings/store'); }}
                />
                <DropdownItem
                  icon={<ArrowLeftRight className="h-4 w-4" />}
                  label="Switch User"
                  onClick={() => setUserMenuOpen(false)}
                />
              </div>

              {/* Logout */}
              <div className="border-t border-surface-100 p-1 dark:border-surface-700">
                <DropdownItem
                  icon={<LogOut className="h-4 w-4" />}
                  label="Log Out"
                  variant="danger"
                  onClick={() => {
                    setUserMenuOpen(false);
                    logout();
                  }}
                />
              </div>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}

function ThemeOption({
  icon,
  label,
  active,
  onClick,
}: {
  icon: React.ReactNode;
  label: string;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={cn(
        'flex w-full items-center gap-2.5 rounded-lg px-2.5 py-2 text-sm transition-colors',
        active
          ? 'bg-brand-50 font-medium text-brand-700 dark:bg-brand-500/10 dark:text-brand-400'
          : 'text-surface-600 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700/50'
      )}
    >
      {icon}
      {label}
      {active && (
        <div className="ml-auto h-1.5 w-1.5 rounded-full bg-brand-500" />
      )}
    </button>
  );
}

function DropdownItem({
  icon,
  label,
  variant = 'default',
  onClick,
}: {
  icon: React.ReactNode;
  label: string;
  variant?: 'default' | 'danger';
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={cn(
        'flex w-full items-center gap-2.5 rounded-lg px-3 py-2 text-sm transition-colors',
        variant === 'danger'
          ? 'text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-500/10'
          : 'text-surface-600 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700/50'
      )}
    >
      {icon}
      {label}
    </button>
  );
}

const notifEntityIcons: Record<string, React.ReactNode> = {
  ticket: <Ticket className="h-4 w-4" />,
  invoice: <FileText className="h-4 w-4" />,
  inventory: <Package className="h-4 w-4" />,
  sms: <MessageSquare className="h-4 w-4" />,
};

function formatTimeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const minutes = Math.floor(diff / 60_000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  return new Date(iso).toLocaleDateString();
}

function NotificationItem({
  notification,
  onClick,
}: {
  notification: Notification;
  onClick: () => void;
}) {
  const icon = notifEntityIcons[notification.entity_type ?? ''] ?? <Info className="h-4 w-4" />;
  const isUnread = !notification.is_read;

  return (
    <button
      onClick={onClick}
      className={cn(
        'flex w-full items-start gap-3 px-4 py-3 text-left transition-colors hover:bg-surface-50 dark:hover:bg-surface-700/50',
        isUnread && 'bg-brand-50/40 dark:bg-brand-500/5'
      )}
    >
      <span className={cn(
        'mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg',
        isUnread
          ? 'bg-brand-100 text-brand-600 dark:bg-brand-500/15 dark:text-brand-400'
          : 'bg-surface-100 text-surface-400 dark:bg-surface-700 dark:text-surface-500'
      )}>
        {icon}
      </span>
      <div className="min-w-0 flex-1">
        <p className={cn(
          'text-sm leading-snug',
          isUnread
            ? 'font-medium text-surface-800 dark:text-surface-100'
            : 'text-surface-600 dark:text-surface-300'
        )}>
          {notification.message}
        </p>
        <p className="mt-0.5 text-xs text-surface-400 dark:text-surface-500">
          {formatTimeAgo(notification.created_at)}
        </p>
      </div>
      {isUnread && (
        <span className="mt-2 h-2 w-2 shrink-0 rounded-full bg-brand-500" />
      )}
    </button>
  );
}
