import { useEffect, useCallback, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { Sidebar } from './Sidebar';
import { Header } from './Header';
import { CommandPalette } from '../shared/CommandPalette';
import { KeyboardShortcutsPanel } from '../shared/KeyboardShortcutsPanel';
import { TrialBanner } from '../shared/TrialBanner';
import { UpgradeModal } from '../shared/UpgradeModal';
import { useUiStore } from '@/stores/uiStore';
import { usePlanStore } from '@/stores/planStore';
import { settingsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { initCurrencyFromSettings } from '@/utils/format';
import { Menu, AlertTriangle, X } from 'lucide-react';
import { useWebSocket } from '@/hooks/useWebSocket';
import { useDismissible } from '@/hooks/useDismissible';
import { GlobalConfirmDialog } from '@/components/shared/GlobalConfirmDialog';
import { ImpersonationBanner } from '@/components/ImpersonationBanner';

// Shape of the augmented config payload returned by `settingsApi.getConfig()`.
// Every field is optional because the server merges store config with env
// metadata; typing them explicitly kills the previous `as any` cast chain.
interface ServerConfigPayload {
  _node_env?: string;
  store_currency?: string;
  [key: string]: unknown;
}

export function AppShell({ children }: { children: React.ReactNode }) {
  const { sidebarCollapsed, mobileSidebarOpen, setMobileSidebarOpen, setCommandPaletteOpen } = useUiStore();
  const [shortcutsPanelOpen, setShortcutsPanelOpen] = useState(false);
  const [devBannerDismissed, dismissDevBanner] = useDismissible('dev-banner');
  const location = useLocation();
  const navigate = useNavigate();

  // Connect to WebSocket when authenticated (AppShell only renders for logged-in users)
  useWebSocket();

  // Fetch tenant plan + usage on mount, refetch on focus
  // SCAN-1146: rapid alt-tab or mobile focus-loss storms previously fired
  // `fetchPlan` on every focus event (`/account/usage` hammered N times
  // per minute). Debounce with a 30-second floor — plan data is slow-
  // changing and dashboards already refetch on reactivation of explicit
  // react-query hooks, so this focus-driven refresh is nice-to-have.
  const fetchPlan = usePlanStore((s) => s.fetchPlan);
  useEffect(() => {
    let lastFetchAt = 0;
    const guardedFetch = (): void => {
      const now = Date.now();
      if (now - lastFetchAt < 30_000) return;
      lastFetchAt = now;
      fetchPlan();
    };
    guardedFetch();
    window.addEventListener('focus', guardedFetch);
    return () => window.removeEventListener('focus', guardedFetch);
  }, [fetchPlan]);

  // Check server environment for dev mode banner.
  // Payload shape: axios response `{ data: { success: true, data: <cfg> } }`
  // where `<cfg>` is the store-config map augmented with `_node_env` and
  // `store_currency` by `settings.routes.ts`.
  const { data: configData } = useQuery<{ data?: { data?: ServerConfigPayload } }>({
    queryKey: ['settings-config-env'],
    queryFn: () => settingsApi.getConfig(),
    staleTime: 5 * 60 * 1000,
  });
  // @audit-fixed: server returns `{ success: true, data: cfg }` where cfg._node_env is
  // set in settings.routes.ts:291. The previous `?.data?._node_env` only unwrapped the
  // axios body once, missing the inner `data` envelope, so _node_env was always undefined
  // and `undefined !== 'production'` evaluated true on EVERY environment — the red dev
  // banner showed in production too. Correct path is body→inner→key (CLAUDE.md "API
  // response shape" — most common bug).
  const isDev = configData?.data?.data?._node_env !== 'production';

  // Initialise shared currency formatter from store settings
  useEffect(() => {
    const currency = configData?.data?.data?.store_currency;
    if (currency) initCurrencyFromSettings(currency);
  }, [configData]);

  // Close mobile sidebar on route change
  useEffect(() => {
    setMobileSidebarOpen(false);
  }, [location.pathname, setMobileSidebarOpen]);

  function isTypingInField(): boolean {
    const target = document.activeElement as HTMLElement | null;
    if (!target) return false;
    const tag = target.tagName;
    return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target.isContentEditable;
  }

  // Global keyboard shortcuts
  // SCAN-1147: Header also registers a `?` listener that opens its own
  // shortcuts dialog — both firing caused two stacked modals and focus-trap
  // conflicts. Header's listener (with matching isEditable guard) already
  // covers the case; drop ours.
  const handleGlobalKeys = useCallback((e: KeyboardEvent) => {
    // Don't trigger shortcuts when typing in inputs or contentEditable elements
    if (isTypingInField()) return;

    switch (e.key) {
      case 'F2': e.preventDefault(); navigate('/pos'); break;
      case 'F3': e.preventDefault(); navigate('/customers/new'); break;
      case 'F4': e.preventDefault(); navigate('/tickets'); break;
      case 'F6': e.preventDefault(); setCommandPaletteOpen(true); break;
    }
  }, [navigate, setCommandPaletteOpen]);

  useEffect(() => {
    window.addEventListener('keydown', handleGlobalKeys);
    return () => window.removeEventListener('keydown', handleGlobalKeys);
  }, [handleGlobalKeys]);

  return (
    <div className="flex h-screen overflow-hidden bg-surface-50 dark:bg-surface-950">
      {/* Mobile backdrop overlay */}
      {mobileSidebarOpen && (
        <div
          className="fixed inset-0 z-40 bg-black/50 md:hidden"
          onClick={() => setMobileSidebarOpen(false)}
        />
      )}

      {/* Sidebar: hidden on mobile unless open, always visible on md+ */}
      <div
        className={cn(
          'fixed inset-y-0 left-0 z-50 transition-transform duration-200 md:translate-x-0 md:z-30',
          mobileSidebarOpen ? 'translate-x-0' : '-translate-x-full'
        )}
      >
        <Sidebar />
      </div>

      <div
        className={cn(
          'flex flex-1 flex-col min-w-0 transition-all duration-200',
          // On desktop, offset by sidebar width; on mobile, no offset
          sidebarCollapsed ? 'md:ml-16' : 'md:ml-64'
        )}
        style={{ '--dev-banner-h': (isDev && !devBannerDismissed) ? '28px' : '0px' } as React.CSSProperties}
      >
        <ImpersonationBanner />
        <Header
          hamburgerButton={
            <button
              onClick={() => setMobileSidebarOpen(true)}
              className="flex h-9 w-9 items-center justify-center rounded-lg text-surface-500 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-200 md:hidden"
              aria-label="Open menu"
            >
              <Menu className="h-5 w-5" />
            </button>
          }
        />
        {isDev && !devBannerDismissed && (
          <div className="relative z-0 flex items-center justify-center gap-2 bg-red-600 px-4 py-1.5 text-xs font-semibold text-white">
            <AlertTriangle className="h-3.5 w-3.5" />
            <span>DEVELOPMENT MODE — NOT SECURE FOR PRODUCTION</span>
            <button
              type="button"
              onClick={dismissDevBanner}
              aria-label="Dismiss development mode warning"
              className="ml-1 rounded p-0.5 transition-colors hover:bg-white/20 focus:outline-none focus:ring-2 focus:ring-white/50"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        )}
        <TrialBanner />
        <main className="flex-1 overflow-auto">
          <div className="p-6 h-full">
            {children}
          </div>
        </main>
      </div>

      {/* Global command palette */}
      <CommandPalette />

      {/* Keyboard shortcuts panel */}
      <KeyboardShortcutsPanel open={shortcutsPanelOpen} onClose={() => setShortcutsPanelOpen(false)} />

      {/* Global confirm dialog */}
      <GlobalConfirmDialog />

      {/* Global upgrade modal (shown when a feature gate is hit) */}
      <UpgradeModal />
    </div>
  );
}
