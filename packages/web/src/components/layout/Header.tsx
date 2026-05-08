import { useState, useRef, useEffect, useCallback, useMemo, memo } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
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
import { notificationDeepLink } from '@/utils/notificationRoutes';
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
  ScrollText,
} from 'lucide-react';
import { ShortcutReferenceCard } from '@/components/onboarding/ShortcutReferenceCard';
import { Button } from '@/components/shared/Button';
// WEB-FAE-001 (partial): adopt the previously-orphan `PermissionBoundary`
// component for the Settings dropdown entry so at least one ad-hoc role
// literal is funneled through the shared gate. Other ad-hoc sites still
// pending a follow-up sweep.
import { PermissionBoundary } from '@/components/shared/PermissionBoundary';

// Module-level constant — moved up from below the component definitions so
// the file reads top-down without an inline surprise between two functions.
// Kept as a plain object (JSX elements are memoised by React's element
// identity, so `Object.freeze` would add no value here).
const notifEntityIcons: Record<string, React.ReactNode> = {
  ticket: <Ticket className="h-4 w-4" />,
  invoice: <FileText className="h-4 w-4" />,
  inventory: <Package className="h-4 w-4" />,
  sms: <MessageSquare className="h-4 w-4" />,
  sms_reminder: <Bell className="h-4 w-4" />,
};

// FD-016: lightweight role-label map. Server stores roles as English keys; the
// UI used to render them raw, leaving non-English tenants reading "admin" /
// "manager" / "technician" untranslated. This object is the single point of
// presentation. Keep server-key-as-fallback so brand-new roles still render
// (capitalised) instead of going blank.
const ROLE_LABELS: Record<string, string> = {
  admin: 'Admin',
  manager: 'Manager',
  technician: 'Technician',
  cashier: 'Cashier',
  owner: 'Owner',
  staff: 'Staff',
};

function formatRoleLabel(role: string | undefined | null): string {
  if (!role) return 'Unknown';
  if (ROLE_LABELS[role]) return ROLE_LABELS[role];
  // Capitalise unknown roles so we never emit raw lower-case slugs to users.
  return role.charAt(0).toUpperCase() + role.slice(1);
}

interface Notification {
  id: number;
  type: string;
  message: string;
  entity_type?: string;
  entity_id?: number;
  is_read: number;
  created_at: string;
}

function isRequestCanceled(err: unknown): boolean {
  if (typeof err !== 'object' || err === null) return false;
  const maybe = err as { code?: unknown; name?: unknown };
  return maybe.code === 'ERR_CANCELED' || maybe.name === 'CanceledError' || maybe.name === 'AbortError';
}

export function Header({ hamburgerButton }: { hamburgerButton?: React.ReactNode }) {
  const navigate = useNavigate();
  const location = useLocation();
  const { setCommandPaletteOpen, keyboardShortcutsEnabled } = useUiStore();
  const { user, logout } = useAuthStore();
  // POS owns its own primary search bar (mockup Frame 03 search prominence).
  // Hide the shell command-palette button on /pos to avoid double search.
  const isPosRoute = location.pathname === '/pos' || location.pathname.startsWith('/pos/') || location.pathname === '/tickets/new';

  const isMac = useMemo(() => /Mac|iPhone|iPad|iPod/.test(navigator.platform || navigator.userAgent), []);
  const shortcutLabel = isMac ? '\u2318K' : 'Ctrl+K';

  const [userMenuOpen, setUserMenuOpen] = useState(false);
  const [notifOpen, setNotifOpen] = useState(false);
  // Day-1 onboarding: shortcut reference card (audit section 42, idea 14).
  // Opened via the ? button in the right-hand action cluster OR by pressing
  // the ? key anywhere on the page (when no modal/input is focused).
  const [shortcutsOpen, setShortcutsOpen] = useState(false);
  const [unreadCount, setUnreadCount] = useState(0);
  // WEB-UIUX-468: separate SR announcement state so the aria-live region only
  // updates on threshold crossings (0→1 and every 10 thereafter) instead of
  // on every WS event. The visible badge still reflects `unreadCount` instantly.
  const [srAnnouncement, setSrAnnouncement] = useState('');
  const prevUnreadRef = useRef(0);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [notifLoading, setNotifLoading] = useState(false);
  const [smsUnreadCount, setSmsUnreadCount] = useState(0);
  const [showSwitchUser, setShowSwitchUser] = useState(false);
  const { switchUser } = useAuthStore();

  // WEB-UIUX-468: fire SR announcement only on meaningful threshold crossings.
  // Thresholds: any transition into 0, the first unread (0→1), and then every
  // multiple of 10. Every other count change stays silent so WS spam doesn't
  // flood screen-reader queues.
  useEffect(() => {
    const prev = prevUnreadRef.current;
    prevUnreadRef.current = unreadCount;
    if (unreadCount === 0 && prev > 0) {
      setSrAnnouncement('No unread notifications');
    } else if (prev === 0 && unreadCount === 1) {
      setSrAnnouncement('1 unread notification');
    } else if (unreadCount > 0 && unreadCount % 10 === 0) {
      setSrAnnouncement(`${unreadCount} unread notifications`);
    }
    // No else — leave srAnnouncement unchanged so the region stays silent.
  }, [unreadCount]);

  const userMenuRef = useRef<HTMLDivElement>(null);
  const notifRef = useRef<HTMLDivElement>(null);
  // WEB-UIUX-466: refs for each menuitem button so arrow-key navigation can
  // move focus programmatically without relying on DOM order queries.
  const menuItemRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const [focusedMenuIndex, setFocusedMenuIndex] = useState(-1);

  // WEB-UIUX-466: focus the first visible menuitem when the menu opens; reset
  // the tracked index when the menu closes so re-opening starts at the top.
  useEffect(() => {
    if (userMenuOpen) {
      setFocusedMenuIndex(0);
      // Defer one tick so the menu is in the DOM before we try to focus.
      setTimeout(() => { menuItemRefs.current[0]?.focus(); }, 0);
    } else {
      setFocusedMenuIndex(-1);
      menuItemRefs.current = [];
    }
  }, [userMenuOpen]);

  // WEB-UIUX-466: handle ArrowDown / ArrowUp / Home / End / Escape within the
  // role="menu" container. Focus wraps at both edges (ARIA APG Menu pattern).
  const handleMenuKeyDown = useCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    const items = menuItemRefs.current.filter(Boolean) as HTMLButtonElement[];
    if (items.length === 0) return;
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      const next = (focusedMenuIndex + 1) % items.length;
      setFocusedMenuIndex(next);
      items[next].focus();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      const prev = (focusedMenuIndex - 1 + items.length) % items.length;
      setFocusedMenuIndex(prev);
      items[prev].focus();
    } else if (e.key === 'Home') {
      e.preventDefault();
      setFocusedMenuIndex(0);
      items[0].focus();
    } else if (e.key === 'End') {
      e.preventDefault();
      const last = items.length - 1;
      setFocusedMenuIndex(last);
      items[last].focus();
    } else if (e.key === 'Escape') {
      setUserMenuOpen(false);
    }
  }, [focusedMenuIndex]);

  const notificationUnreadAbortRef = useRef<AbortController | null>(null);
  const smsUnreadAbortRef = useRef<AbortController | null>(null);
  const notificationListAbortRef = useRef<AbortController | null>(null);
  // WEB-FO-009: keep a mount guard alongside AbortController. Axios will
  // cancel most in-flight work, while the ref covers races where a promise
  // resolves right as logout/route teardown happens.
  const isMountedRef = useRef(true);
  const abortHeaderFetches = useCallback(() => {
    notificationUnreadAbortRef.current?.abort();
    notificationUnreadAbortRef.current = null;
    smsUnreadAbortRef.current?.abort();
    smsUnreadAbortRef.current = null;
    notificationListAbortRef.current?.abort();
    notificationListAbortRef.current = null;
  }, []);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
      abortHeaderFetches();
    };
  }, [abortHeaderFetches]);

  // Fetch unread count on mount + on visibility-change resume.
  // @audit-fixed (WEB-FO-006 / Fixer-B12 2026-04-25): dropped the 60s
  // setInterval entirely. WS already pushes NOTIFICATION_NEW + SMS_RECEIVED
  // through useWebSocket → invalidates ['notification-count']. The interval
  // duplicated that work and doubled backend load on the bell counter (50
  // sessions/tenant ≈ 100 wasted req/min). The visibility-resume fetch is
  // kept as a recovery for missed WS events while the tab was hidden.
  // Previous fixes: WEB-FAD-002 (30s→60s + visibility gate), Fixer-PPP
  // WEB-FO-019 (park-on-hidden).
  const fetchUnreadCount = useCallback(async () => {
    notificationUnreadAbortRef.current?.abort();
    const controller = new AbortController();
    notificationUnreadAbortRef.current = controller;
    try {
      const res = await notificationApi.unreadCount(controller.signal);
      if (
        !isMountedRef.current ||
        controller.signal.aborted ||
        notificationUnreadAbortRef.current !== controller
      ) return;
      setUnreadCount(res.data?.data?.count ?? 0);
    } catch (err: unknown) {
      if (isRequestCanceled(err)) return;
      // Silently handled — count stays at previous value
    } finally {
      if (notificationUnreadAbortRef.current === controller) {
        notificationUnreadAbortRef.current = null;
      }
    }
  }, []);

  const fetchSmsUnreadCount = useCallback(async () => {
    smsUnreadAbortRef.current?.abort();
    const controller = new AbortController();
    smsUnreadAbortRef.current = controller;
    try {
      const res = await smsApi.unreadCount(controller.signal);
      if (
        !isMountedRef.current ||
        controller.signal.aborted ||
        smsUnreadAbortRef.current !== controller
      ) return;
      setSmsUnreadCount(res.data?.data?.count ?? 0);
    } catch (err: unknown) {
      if (isRequestCanceled(err)) return;
      // Silently handled — count stays at previous value
    } finally {
      if (smsUnreadAbortRef.current === controller) {
        smsUnreadAbortRef.current = null;
      }
    }
  }, []);

  useEffect(() => {
    // WEB-FD-011 (Fixer-OOO 2026-04-25): short-circuit polling when the
    // session is already cleared so logout doesn't fire a 401 storm against
    // notification + sms unread-count endpoints (which then push another
    // logout-required event through the response interceptor and re-trigger
    // refresh). We additionally listen for `bizarre-crm:auth-cleared` so an
    // in-flight tick that fires DURING logout (between authStore set and
    // the next render) tears the interval down immediately rather than
    // waiting for unmount.
    let cancelled = false;
    const isAuthed = () => useAuthStore.getState().isAuthenticated;

    if (isAuthed()) {
      fetchUnreadCount();
      fetchSmsUnreadCount();
    }

    // Resume fetch immediately when tab becomes visible again — recovery
    // for any WS events missed while the tab was hidden. No background
    // interval; WS handles the live-update path.
    const handleVisibilityChange = () => {
      if (cancelled) return;
      if (!isAuthed()) return;
      if (document.visibilityState === 'visible') {
        fetchUnreadCount();
        fetchSmsUnreadCount();
      }
    };
    const handleAuthCleared = () => {
      cancelled = true;
      abortHeaderFetches();
    };
    document.addEventListener('visibilitychange', handleVisibilityChange);
    window.addEventListener('bizarre-crm:auth-cleared', handleAuthCleared);

    return () => {
      cancelled = true;
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      window.removeEventListener('bizarre-crm:auth-cleared', handleAuthCleared);
    };
  }, [abortHeaderFetches, fetchUnreadCount, fetchSmsUnreadCount]);

  // Fetch notifications when dropdown opens
  const fetchNotifications = useCallback(async () => {
    notificationListAbortRef.current?.abort();
    const controller = new AbortController();
    notificationListAbortRef.current = controller;
    setNotifLoading(true);
    try {
      const res = await notificationApi.list({ pagesize: 10 }, controller.signal);
      if (
        !isMountedRef.current ||
        controller.signal.aborted ||
        notificationListAbortRef.current !== controller
      ) return;
      setNotifications(res.data?.data?.notifications ?? []);
    } catch (err: unknown) {
      if (isRequestCanceled(err)) return;
      // Silently handled — notifications stay at previous state
    } finally {
      // Guard the loading flag too — same unmount race.
      if (notificationListAbortRef.current === controller) {
        notificationListAbortRef.current = null;
        if (isMountedRef.current) setNotifLoading(false);
      }
    }
  }, []);

  const handleBellClick = useCallback(() => {
    const opening = !notifOpen;
    setNotifOpen(opening);
    if (opening) {
      setUserMenuOpen(false); // mutex: close user menu
      fetchNotifications();
    } else {
      notificationListAbortRef.current?.abort();
      notificationListAbortRef.current = null;
      setNotifLoading(false);
    }
  }, [notifOpen, fetchNotifications]);

  const handleMarkAllRead = useCallback(async () => {
    try {
      await notificationApi.markAllRead();
      if (!isMountedRef.current) return;
      setUnreadCount(0);
      setNotifications((prev) => prev.map((n) => ({ ...n, is_read: 1 })));
    } catch (err: unknown) {
      if (!isMountedRef.current) return;
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
        if (!isMountedRef.current) return;
        console.error('[notifications] markRead failed', err);
        setUnreadCount((c) => c + 1);
        setNotifications((prev) =>
          prev.map((n) => (n.id === notif.id ? { ...n, is_read: 0 } : n))
        );
        toast.error('Could not mark notification read');
      }
    }
    // Navigate to entity (WEB-FL-016: route map hoisted to utils/notificationRoutes
    // so the server entity_type taxonomy stays alignable + unit-testable).
    const deepLink = notificationDeepLink(notif.entity_type, notif.entity_id);
    if (deepLink) navigate(deepLink);
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
  //
  // WEB-UIUX-295: WCAG 2.1.4 — single-key shortcuts must be disableable.
  // Cmd+K / Ctrl+K are modifier-keyed (not affected). Bare "?" is gated
  // behind keyboardShortcutsEnabled so users who opt out aren't triggered.
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        setCommandPaletteOpen(true);
        return;
      }
      // Bare "?" is a single-key shortcut — respect user's WCAG opt-out.
      if (!keyboardShortcutsEnabled) return;
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
    [keyboardShortcutsEnabled, setCommandPaletteOpen]
  );

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);

  const initials = user
    ? `${user.first_name?.[0] ?? ''}${user.last_name?.[0] ?? ''}`.toUpperCase() || '?'
    : '?';

  return (
    <header data-app-chrome="true" className={cn(
      "relative z-40 flex shrink-0 items-center gap-4 border-b border-surface-200 bg-white/80 px-4 sm:px-6 backdrop-blur-sm dark:border-surface-800 dark:bg-surface-900/80",
      isPosRoute ? "h-14" : "h-16",
    )} style={{ overflow: 'visible' }}>
      {/* Left: Hamburger (mobile) + Breadcrumb area (placeholder) */}
      <div className={cn("flex items-center gap-2", isPosRoute ? "flex-none" : "flex-1")}>
        {hamburgerButton}
      </div>

      {/* Center: Search — hidden on /pos because POS owns its own primary search bar.
          On /pos, render a portal slot so POS can hoist its title+search+actions up here. */}
      {!isPosRoute && (
        <Button
          onClick={() => setCommandPaletteOpen(true)}
          variant="secondary"
          size="sm"
          fullWidth
          className="max-w-md !justify-start gap-2 border-surface-200 bg-surface-50 text-surface-400 hover:border-surface-300 hover:bg-surface-100 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-500 dark:hover:border-surface-600 dark:hover:bg-surface-750"
          aria-keyshortcuts="Meta+K Control+K F6"
        >
          <Search className="h-4 w-4 shrink-0" />
          <span className="flex-1 text-left">Search or press {shortcutLabel}...</span>
          <kbd className="hidden rounded border border-surface-200 bg-white px-1.5 py-0.5 text-[11px] font-medium text-surface-400 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-400 sm:inline-block">
            {shortcutLabel}
          </kbd>
        </Button>
      )}
      {isPosRoute && <div id="pos-header-slot" className="flex flex-1 items-center gap-3 min-w-0" />}

      {/* Right: Actions */}
      {/* Theme toggle was previously here but has been moved to Settings > Store.
          The wizard (StepWelcome) collects it on first-run; subsequent changes
          happen from Settings. Keeping the header focused on immediate actions
          (search, notifications, messages, user menu) reduces noise. */}
      <div className={cn("flex items-center justify-end gap-1", isPosRoute ? "ml-auto" : "flex-1")}>
        {/* Keyboard shortcut reference (audit section 42, idea 14) */}
        <Button
          onClick={() => setShortcutsOpen(true)}
          variant="ghost"
          size="sm"
          iconOnly
          className="relative hidden min-h-[44px] min-w-[44px] text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200 sm:flex md:min-h-0 md:min-w-0"
          title="Keyboard shortcuts (press ?)"
          aria-label="Keyboard shortcuts"
          aria-keyshortcuts="?"
        >
          <HelpCircle className="h-4.5 w-4.5" />
        </Button>

        {/* SMS quick-access */}
        <Button
          onClick={() => navigate('/communications')}
          variant="ghost"
          size="sm"
          iconOnly
          className="relative min-h-[44px] min-w-[44px] text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200 md:min-h-0 md:min-w-0"
          title="Messages"
          aria-label="Messages"
        >
          <MessageSquare className="h-4.5 w-4.5" />
          {smsUnreadCount > 0 && (
            <span className="absolute -right-0.5 -top-0.5 flex h-4.5 min-w-[18px] items-center justify-center rounded-full bg-success-500 px-1 text-[10px] font-bold leading-none text-white shadow-sm">
              {smsUnreadCount > 99 ? '99+' : smsUnreadCount}
            </span>
          )}
        </Button>

        {/* Notifications */}
        <div ref={notifRef} className="relative">
          {/* WEB-UIUX-468: only announce threshold crossings (0→1, every 10,
              cleared to 0) — not every WS increment — to avoid SR spam. */}
          <span className="sr-only" aria-live="polite" aria-atomic="true">
            {srAnnouncement}
          </span>
          <Button
            onClick={handleBellClick}
            variant="ghost"
            size="sm"
            iconOnly
            className={cn(
              'relative min-h-[44px] min-w-[44px] text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200 md:min-h-0 md:min-w-0',
              notifOpen && 'bg-surface-100 dark:bg-surface-800'
            )}
            title="Notifications"
            aria-label="Notifications"
            aria-haspopup="true"
            aria-expanded={notifOpen}
          >
            <Bell className="h-4.5 w-4.5" />
            {unreadCount > 0 && (
              <span className="absolute -right-0.5 -top-0.5 flex h-4.5 min-w-[18px] items-center justify-center rounded-full bg-error-500 px-1 text-[10px] font-bold leading-none text-white shadow-sm">
                {unreadCount > 99 ? '99+' : unreadCount}
              </span>
            )}
          </Button>

          {notifOpen && (
            <div className="absolute right-0 top-full z-50 mt-1.5 w-72 max-w-[calc(100vw-1rem)] overflow-hidden rounded-xl border border-surface-200 bg-white shadow-lg sm:w-80 dark:border-surface-700 dark:bg-surface-800">
              {/* Header */}
              <div className="flex items-center justify-between border-b border-surface-100 px-4 py-3 dark:border-surface-700">
                <p className="text-sm font-semibold text-surface-800 dark:text-surface-100">
                  Notifications
                </p>
                {unreadCount > 0 && (
                  <Button
                    onClick={handleMarkAllRead}
                    variant="ghost"
                    size="xs"
                    className="gap-1 text-brand-600 hover:bg-transparent hover:text-brand-700 dark:text-brand-400 dark:hover:bg-transparent dark:hover:text-brand-300"
                  >
                    <CheckCheck className="h-3.5 w-3.5" />
                    Mark all read
                  </Button>
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
                      onSelect={handleNotifClick}
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
          <Button
            onClick={() => { setUserMenuOpen((o) => { if (!o) setNotifOpen(false); return !o; }); }}
            variant="ghost"
            size="sm"
            className={cn(
              'gap-2 px-2 min-h-[44px] md:min-h-0',
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
                {formatRoleLabel(user?.role)}
              </p>
            </div>
            <ChevronDown
              className={cn(
                'hidden h-4 w-4 text-surface-400 transition-transform md:block',
                userMenuOpen && 'rotate-180'
              )}
            />
          </Button>

          {userMenuOpen && (
            // WEB-UIUX-466: onKeyDown + menuItemRefs enable ArrowDown/Up navigation.
            // eslint-disable-next-line jsx-a11y/interactive-supports-focus
            <div role="menu" aria-label="User menu" onKeyDown={handleMenuKeyDown} className="absolute right-0 top-full z-50 mt-1.5 w-56 overflow-hidden rounded-xl border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
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
              {/* WEB-UIUX-466: clear the ref slot array each render so hidden
                  items (behind PermissionBoundary) don't leave stale refs. */}
              <div className="p-1" ref={() => { menuItemRefs.current = []; }}>
                <DropdownItem
                  icon={<User className="h-4 w-4" />}
                  label="Profile"
                  itemRef={(el) => { menuItemRefs.current[menuItemRefs.current.length] = el; }}
                  onClick={() => { setUserMenuOpen(false); navigate('/settings/users'); }}
                />
                {/* SCAN-1145: managers have settings.edit server-side — let
                    them see the Settings link too. WEB-FAE-001: routed
                    through the canonical `PermissionBoundary` so the role
                    list is shared with the rest of the app and a future
                    `useHasRole` migration only has to touch one component. */}
                <PermissionBoundary roles={['admin', 'manager']}>
                  <DropdownItem
                    icon={<Settings className="h-4 w-4" />}
                    label="Settings"
                    itemRef={(el) => { menuItemRefs.current[menuItemRefs.current.length] = el; }}
                    onClick={() => { setUserMenuOpen(false); navigate('/settings/store'); }}
                  />
                </PermissionBoundary>
                {/* WEB-FL-017 (Fixer-C7 2026-04-25): Audit Logs is a defined
                    Settings tab but had no entry surface — admins reached it
                    only by clicking through the Settings tab list, which is
                    the worst path during a security incident. Add a direct
                    deep-link from the user menu, gated to admin since the
                    server settings.routes.ts permission check rejects
                    non-admins anyway (a manager-visible link would dead-end
                    on a 403 toast). */}
                <PermissionBoundary roles={['admin']}>
                  <DropdownItem
                    icon={<ScrollText className="h-4 w-4" />}
                    label="Audit Logs"
                    itemRef={(el) => { menuItemRefs.current[menuItemRefs.current.length] = el; }}
                    onClick={() => { setUserMenuOpen(false); navigate('/settings/audit-logs'); }}
                  />
                </PermissionBoundary>
                <DropdownItem
                  icon={<ArrowLeftRight className="h-4 w-4" />}
                  label="Switch User"
                  itemRef={(el) => { menuItemRefs.current[menuItemRefs.current.length] = el; }}
                  onClick={() => { setUserMenuOpen(false); setShowSwitchUser(true); }}
                />
              </div>

              {/* Logout */}
              <div className="border-t border-surface-100 p-1 dark:border-surface-700">
                <DropdownItem
                  icon={<LogOut className="h-4 w-4" />}
                  label="Log Out"
                  variant="danger"
                  itemRef={(el) => { menuItemRefs.current[menuItemRefs.current.length] = el; }}
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

// WEB-UIUX-466: itemRef is a callback ref forwarded to the inner Button element
// so the parent can build the menuItemRefs array used for arrow-key navigation.
function DropdownItem({
  icon,
  label,
  variant = 'default',
  itemRef,
  onClick,
}: {
  icon: React.ReactNode;
  label: string;
  variant?: 'default' | 'danger';
  itemRef?: (el: HTMLButtonElement | null) => void;
  onClick: () => void;
}) {
  return (
    <Button
      ref={itemRef}
      role="menuitem"
      onClick={onClick}
      variant="ghost"
      size="sm"
      fullWidth
      className={cn(
        '!justify-start gap-2.5',
        variant === 'danger'
          ? 'text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-500/10'
          : 'text-surface-600 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700/50'
      )}
    >
      {icon}
      {label}
    </Button>
  );
}

// @audit-fixed: removed local `formatTimeAgo` — now uses the shared `timeAgo`
// helper imported at the top of the file. The local copy missed the UTC suffix
// fix-up that the shared helper applies for server timestamps stored without
// a trailing `Z`, leading to off-by-timezone "1h ago" labels in some setups.

const NotificationItem = memo(function NotificationItem({
  notification,
  onSelect,
}: {
  notification: Notification;
  onSelect: (notification: Notification) => void;
}) {
  const icon = notifEntityIcons[notification.entity_type ?? ''] ?? <Info className="h-4 w-4" />;
  const isUnread = !notification.is_read;

  return (
    <button
      onClick={() => onSelect(notification)}
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

// WEB-UIUX-474: mirror PinModal's 5-attempt lockout + data-lpignore here.
// We cannot reuse <PinModal> directly because PinModal calls authApi.verifyPin
// internally and returns no pin value; SwitchUserModal must pass the raw PIN
// to switchUser() externally. Duplicating only the lockout state (not the
// full component) is the minimal, safe fix.
const SWITCH_MAX_ATTEMPTS = 5;
const SWITCH_LOCKOUT_SECONDS = 60;

function SwitchUserModal({ onSuccess, onCancel }: { onSuccess: (pin: string) => Promise<void>; onCancel: () => void }) {
  const [pin, setPin] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [failCount, setFailCount] = useState(0);
  const [lockedUntil, setLockedUntil] = useState<number | null>(null);
  const [lockCountdown, setLockCountdown] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const cancelButtonRef = useRef<HTMLButtonElement>(null);

  const isLocked = lockedUntil !== null && Date.now() < lockedUntil;

  useEffect(() => { inputRef.current?.focus(); }, []);

  // Esc closes the dialog. The page-wide Esc handler elsewhere in this file
  // targets dropdown menus only; without this listener the modal would only
  // close via the X / Cancel buttons.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onCancel(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onCancel]);

  // Countdown timer while locked out — matches PinModal pattern.
  useEffect(() => {
    if (!lockedUntil) return;
    const tick = () => {
      const remaining = Math.ceil((lockedUntil - Date.now()) / 1000);
      if (remaining <= 0) {
        setLockedUntil(null);
        setLockCountdown(0);
        setError('');
        setFailCount(0);
        inputRef.current?.focus();
      } else {
        setLockCountdown(remaining);
      }
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [lockedUntil]);

  // WEB-UIUX-445: move focus to Cancel when lockout activates so the user
  // has a reachable, actionable target (PIN input becomes disabled).
  useEffect(() => {
    if (isLocked) cancelButtonRef.current?.focus();
  }, [isLocked]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pin.trim() || loading || isLocked) return;
    setLoading(true);
    setError('');
    try {
      await onSuccess(pin);
    } catch (err) {
      // Underlying error already mapped to a UI banner; log so the actual cause
      // (network vs auth vs server) is visible in console / Sentry.
      console.warn('[SwitchUserModal] PIN switch failed', err);
      const newCount = failCount + 1;
      setFailCount(newCount);
      if (newCount >= SWITCH_MAX_ATTEMPTS) {
        const lockTs = Date.now() + SWITCH_LOCKOUT_SECONDS * 1000;
        setLockedUntil(lockTs);
        setError(`Too many attempts. Please wait ${SWITCH_LOCKOUT_SECONDS}s.`);
      } else {
        setError(`Invalid PIN (${SWITCH_MAX_ATTEMPTS - newCount} attempts remaining)`);
      }
      setPin('');
      inputRef.current?.focus();
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      onClick={onCancel}
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="switch-user-title"
        className="relative w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-900"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-3 dark:border-surface-700">
          <div className="flex items-center gap-2">
            <ArrowLeftRight className="h-4 w-4 text-surface-500" />
            <h2 id="switch-user-title" className="text-base font-semibold text-surface-900 dark:text-surface-50">Switch User</h2>
          </div>
          <Button aria-label="Close" onClick={onCancel} variant="ghost" size="sm" iconOnly className="min-h-[44px] min-w-[44px] text-surface-400 md:min-h-0 md:min-w-0">
            <X className="h-5 w-5" />
          </Button>
        </div>
        <form onSubmit={handleSubmit} className="px-5 py-4 space-y-4">
          <p className="text-sm text-surface-500 dark:text-surface-400">Enter the PIN of the user to switch to.</p>
          {/* SCAN-1163: data-lpignore + autoComplete="off" + data-form-type="other"
              prevent password managers from offering to save the switch PIN. */}
          <input
            ref={inputRef}
            type="password"
            inputMode="numeric"
            pattern="[0-9]*"
            maxLength={6}
            value={pin}
            disabled={isLocked}
            autoComplete="off"
            data-lpignore="true"
            data-form-type="other"
            onChange={(e) => { if (!isLocked) { setPin(e.target.value.replace(/\D/g, '')); setError(''); } }}
            placeholder={isLocked ? `Wait ${lockCountdown}s` : 'PIN'}
            className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-center text-2xl tracking-[0.5em] focus:border-primary-600 focus-visible:outline-none focus:ring-1 focus:ring-primary-600 disabled:opacity-50 disabled:cursor-not-allowed dark:border-surface-600 dark:bg-surface-800 dark:text-surface-50"
          />
          {isLocked && (
            <p role="alert" aria-live="polite" className="text-center text-sm text-amber-600 dark:text-amber-400">
              Locked. Press Cancel to close.
            </p>
          )}
          {error && !isLocked && <p className="text-center text-sm text-red-500">{error}</p>}
          <div className="flex gap-3">
            <Button ref={cancelButtonRef} type="button" onClick={onCancel} variant="secondary" size="sm" fullWidth>
              Cancel
            </Button>
            <Button
              type="submit"
              disabled={!pin.trim() || loading || isLocked}
              variant="primary"
              size="sm"
              fullWidth
              leadingIcon={loading ? <Loader2 className="h-4 w-4 animate-spin" /> : undefined}
            >
              Switch
            </Button>
          </div>
        </form>
      </div>
    </div>
  );
}
