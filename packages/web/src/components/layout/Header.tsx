import { useState, useRef, useEffect, useCallback, useMemo, memo } from 'react';
import { useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { useUiStore } from '@/stores/uiStore';
import { useAuthStore } from '@/stores/authStore';
import { notificationApi, smsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
// @audit-fixed: Header used to define a private `formatTimeAgo` (line ~487)
// that duplicated `timeAgo` in utils/format.ts. Reusing the shared helper
// keeps the relative-time output consistent across pages and respects the
// shared UTC handling for server timestamps without trailing 'Z'.
import { timeAgo } from '@/utils/format';
import {
  Search,
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
  X,
  Loader2,
  HelpCircle,
} from 'lucide-react';
import { ShortcutReferenceCard } from '@/components/onboarding/ShortcutReferenceCard';

// Module-level constant — moved up from below the component definitions so
// the file reads top-down without an inline surprise between two functions.
// Kept as a plain object (JSX elements are memoised by React's element
// identity, so `Object.freeze` would add no value here).
const notifEntityIcons: Record<string, React.ReactNode> = {
  ticket: <Ticket className="h-4 w-4" />,
  invoice: <FileText className="h-4 w-4" />,
  inventory: <Package className="h-4 w-4" />,
  sms: <MessageSquare className="h-4 w-4" />,
};

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
  const { setCommandPaletteOpen } = useUiStore();
  const { user, logout } = useAuthStore();

  const isMac = useMemo(() => /Mac|iPhone|iPad|iPod/.test(navigator.platform || navigator.userAgent), []);
  const shortcutLabel = isMac ? '\u2318K' : 'Ctrl+K';

  const [userMenuOpen, setUserMenuOpen] = useState(false);
  const [notifOpen, setNotifOpen] = useState(false);
  // Day-1 onboarding: shortcut reference card (audit section 42, idea 14).
  // Opened via the ? button in the right-hand action cluster OR by pressing
  // the ? key anywhere on the page (when no modal/input is focused).
  const [shortcutsOpen, setShortcutsOpen] = useState(false);
  const [unreadCount, setUnreadCount] = useState(0);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [notifLoading, setNotifLoading] = useState(false);
  const [smsUnreadCount, setSmsUnreadCount] = useState(0);
  const [showSwitchUser, setShowSwitchUser] = useState(false);
  const { switchUser } = useAuthStore();

  const userMenuRef = useRef<HTMLDivElement>(null);
  const notifRef = useRef<HTMLDivElement>(null);

  // Fetch unread count on mount + poll every 30s
  const fetchUnreadCount = useCallback(async () => {
    try {
      const res = await notificationApi.unreadCount();
      setUnreadCount(res.data?.data?.count ?? 0);
    } catch (err: unknown) {
      // Silently handled — count stays at previous value
    }
  }, []);

  const fetchSmsUnreadCount = useCallback(async () => {
    try {
      const res = await smsApi.unreadCount();
      setSmsUnreadCount(res.data?.data?.count ?? 0);
    } catch (err: unknown) {
      // Silently handled — count stays at previous value
    }
  }, []);

  useEffect(() => {
    fetchUnreadCount();
    fetchSmsUnreadCount();

    const pollIfVisible = () => {
      if (document.visibilityState === 'visible') {
        fetchUnreadCount();
        fetchSmsUnreadCount();
      }
    };

    const interval = setInterval(pollIfVisible, 30_000);

    // Resume polling immediately when tab becomes visible again
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        fetchUnreadCount();
        fetchSmsUnreadCount();
      }
    };
    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      clearInterval(interval);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [fetchUnreadCount, fetchSmsUnreadCount]);

  // Fetch notifications when dropdown opens
  const fetchNotifications = useCallback(async () => {
    setNotifLoading(true);
    try {
      const res = await notificationApi.list({ pagesize: 10 });
      setNotifications(res.data?.data?.notifications ?? []);
    } catch (err: unknown) {
      // Silently handled — notifications stay at previous state
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
    } catch (err: unknown) {
      // Server refused the mark-all. Surface the failure so the user knows
      // the badge count they see is still the stale one.
      console.error('[notifications] markAllRead failed', err);
      toast.error('Could not mark all notifications read');
    }
  }, []);

  const handleNotifClick = useCallback(async (notif: Notification) => {
    // Mark as read — optimistically flip the row + decrement the badge,
    // then roll back if the server refuses so the UI doesn't drift.
    if (!notif.is_read) {
      setUnreadCount((c) => Math.max(0, c - 1));
      setNotifications((prev) =>
        prev.map((n) => (n.id === notif.id ? { ...n, is_read: 1 } : n))
      );
      try {
        await notificationApi.markRead(notif.id);
      } catch (err: unknown) {
        console.error('[notifications] markRead failed', err);
        setUnreadCount((c) => c + 1);
        setNotifications((prev) =>
          prev.map((n) => (n.id === notif.id ? { ...n, is_read: 0 } : n))
        );
        toast.error('Could not mark notification read');
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
      if (notifRef.current && !notifRef.current.contains(e.target as Node)) {
        setNotifOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Close menus on Escape key
  useEffect(() => {
    const anyOpen = userMenuOpen || notifOpen;
    if (!anyOpen) return;
    function handleEscape(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        setUserMenuOpen(false);
        setNotifOpen(false);
      }
    }
    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [userMenuOpen, notifOpen]);

  // Cmd+K / Ctrl+K shortcut, plus "?" to open the shortcut reference
  // card (audit section 42, idea 14). The "?" binding is suppressed when
  // the user is typing in an input/textarea so they can still type an actual
  // question mark into forms.
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        setCommandPaletteOpen(true);
        return;
      }
      if (e.key === '?' && !e.metaKey && !e.ctrlKey && !e.altKey) {
        const target = e.target as HTMLElement | null;
        const isEditable =
          target &&
          (target.tagName === 'INPUT' ||
            target.tagName === 'TEXTAREA' ||
            target.isContentEditable);
        if (!isEditable) {
          e.preventDefault();
          setShortcutsOpen(true);
        }
      }
    },
    [setCommandPaletteOpen]
  );

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);

  const initials = user
    ? `${user.first_name?.[0] ?? ''}${user.last_name?.[0] ?? ''}`.toUpperCase() || '?'
    : '?';

  return (
    <header className="relative z-40 flex h-16 shrink-0 items-center gap-4 border-b border-surface-200 bg-white/80 px-4 sm:px-6 backdrop-blur-sm dark:border-surface-800 dark:bg-surface-900/80" style={{ overflow: 'visible' }}>
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
      {/* Theme toggle was previously here but has been moved to Settings > Store.
          The wizard (StepWelcome) collects it on first-run; subsequent changes
          happen from Settings. Keeping the header focused on immediate actions
          (search, notifications, messages, user menu) reduces noise. */}
      <div className="flex flex-1 items-center justify-end gap-1">
        {/* Keyboard shortcut reference (audit section 42, idea 14) */}
        <button
          onClick={() => setShortcutsOpen(true)}
          className="relative hidden min-h-[44px] min-w-[44px] md:h-9 md:w-9 md:min-h-0 md:min-w-0 items-center justify-center rounded-lg text-surface-500 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-200 sm:flex"
          title="Keyboard shortcuts (press ?)"
          aria-label="Keyboard shortcuts"
        >
          <HelpCircle className="h-4.5 w-4.5" />
        </button>

        {/* SMS quick-access */}
        <button
          onClick={() => navigate('/communications')}
          className="relative flex min-h-[44px] min-w-[44px] md:h-9 md:w-9 md:min-h-0 md:min-w-0 items-center justify-center rounded-lg text-surface-500 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-200"
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
              'relative flex min-h-[44px] min-w-[44px] md:h-9 md:w-9 md:min-h-0 md:min-w-0 items-center justify-center rounded-lg text-surface-500 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-200',
              notifOpen && 'bg-surface-100 dark:bg-surface-800'
            )}
            title="Notifications"
            aria-label="Notifications"
            aria-haspopup="true"
            aria-expanded={notifOpen}
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
              'flex items-center gap-2 rounded-lg px-2 min-h-[44px] md:min-h-0 md:py-1.5 transition-colors hover:bg-surface-100 dark:hover:bg-surface-800',
              userMenuOpen && 'bg-surface-100 dark:bg-surface-800'
            )}
            aria-label="User menu"
            aria-haspopup="menu"
            aria-expanded={userMenuOpen}
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
            <div role="menu" aria-label="User menu" className="absolute right-0 top-full z-50 mt-1.5 w-56 overflow-hidden rounded-xl border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
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
              {/* @audit-fixed: Settings (store config) is admin-only on the
                  server (settings.routes.ts gates writes by role). Hiding the
                  link for non-admin users avoids the dead-click → 403 →
                  "you don't have access" toast every technician hit. The
                  Profile link still shows because /settings/users self-edit
                  is permitted for the current user. */}
              <div className="p-1">
                <DropdownItem
                  icon={<User className="h-4 w-4" />}
                  label="Profile"
                  onClick={() => { setUserMenuOpen(false); navigate('/settings/users'); }}
                />
                {user?.role === 'admin' && (
                  <DropdownItem
                    icon={<Settings className="h-4 w-4" />}
                    label="Settings"
                    onClick={() => { setUserMenuOpen(false); navigate('/settings/store'); }}
                  />
                )}
                <DropdownItem
                  icon={<ArrowLeftRight className="h-4 w-4" />}
                  label="Switch User"
                  onClick={() => { setUserMenuOpen(false); setShowSwitchUser(true); }}
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

      {/* Switch User PIN Modal */}
      {showSwitchUser && (
        <SwitchUserModal
          onSuccess={async (pin: string) => {
            try {
              await switchUser(pin);
              toast.success('Switched user');
              setShowSwitchUser(false);
              navigate('/');
            } catch (err: unknown) {
              throw err; // re-throw so modal shows error
            }
          }}
          onCancel={() => setShowSwitchUser(false)}
        />
      )}

      {/* Day-1 onboarding: keyboard shortcut reference card */}
      <ShortcutReferenceCard open={shortcutsOpen} onClose={() => setShortcutsOpen(false)} />
    </header>
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
      role="menuitem"
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

// @audit-fixed: removed local `formatTimeAgo` — now uses the shared `timeAgo`
// helper imported at the top of the file. The local copy missed the UTC suffix
// fix-up that the shared helper applies for server timestamps stored without
// a trailing `Z`, leading to off-by-timezone "1h ago" labels in some setups.

const NotificationItem = memo(function NotificationItem({
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
          {timeAgo(notification.created_at)}
        </p>
      </div>
      {isUnread && (
        <span className="mt-2 h-2 w-2 shrink-0 rounded-full bg-brand-500" />
      )}
    </button>
  );
});

function SwitchUserModal({ onSuccess, onCancel }: { onSuccess: (pin: string) => Promise<void>; onCancel: () => void }) {
  const [pin, setPin] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => { inputRef.current?.focus(); }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pin.trim() || loading) return;
    setLoading(true);
    setError('');
    try {
      await onSuccess(pin);
    } catch {
      setError('Invalid PIN or switch failed');
      setPin('');
      inputRef.current?.focus();
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="relative w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-900">
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-3 dark:border-surface-700">
          <div className="flex items-center gap-2">
            <ArrowLeftRight className="h-4 w-4 text-surface-500" />
            <h2 className="text-base font-semibold text-surface-900 dark:text-surface-50">Switch User</h2>
          </div>
          <button aria-label="Close" onClick={onCancel} className="inline-flex items-center justify-center rounded-lg text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800 min-h-[44px] min-w-[44px] md:min-h-0 md:min-w-0 md:p-1">
            <X className="h-5 w-5" />
          </button>
        </div>
        <form onSubmit={handleSubmit} className="px-5 py-4 space-y-4">
          <p className="text-sm text-surface-500 dark:text-surface-400">Enter the PIN of the user to switch to.</p>
          <input
            ref={inputRef}
            type="password"
            inputMode="numeric"
            pattern="[0-9]*"
            maxLength={6}
            value={pin}
            onChange={(e) => { setPin(e.target.value.replace(/\D/g, '')); setError(''); }}
            placeholder="PIN"
            className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-center text-2xl tracking-[0.5em] focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-50"
          />
          {error && <p className="text-center text-sm text-red-500">{error}</p>}
          <div className="flex gap-3">
            <button type="button" onClick={onCancel}
              className="flex-1 rounded-lg border border-surface-300 px-4 py-2.5 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800">
              Cancel
            </button>
            <button type="submit" disabled={!pin.trim() || loading}
              className="flex flex-1 items-center justify-center gap-2 rounded-lg bg-teal-600 px-4 py-2.5 text-sm font-medium text-white hover:bg-teal-700 disabled:opacity-50">
              {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Switch'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
