import { useEffect, useCallback, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { Sidebar } from './Sidebar';
import { Header } from './Header';
import { CommandPalette } from '../shared/CommandPalette';
import { KeyboardShortcutsPanel } from '../shared/KeyboardShortcutsPanel';
import { useUiStore } from '@/stores/uiStore';
import { settingsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { initCurrencyFromSettings } from '@/utils/format';
import { Menu, AlertTriangle } from 'lucide-react';
import { useWebSocket } from '@/hooks/useWebSocket';
import { GlobalConfirmDialog } from '@/components/shared/GlobalConfirmDialog';

export function AppShell({ children }: { children: React.ReactNode }) {
  const { sidebarCollapsed, mobileSidebarOpen, setMobileSidebarOpen, setCommandPaletteOpen } = useUiStore();
  const [shortcutsPanelOpen, setShortcutsPanelOpen] = useState(false);
  const location = useLocation();
  const navigate = useNavigate();

  // Connect to WebSocket when authenticated (AppShell only renders for logged-in users)
  useWebSocket();

  // Check server environment for dev mode banner
  const { data: configData } = useQuery({
    queryKey: ['settings-config-env'],
    queryFn: () => settingsApi.getConfig(),
    staleTime: 5 * 60 * 1000,
  });
  const isDev = (configData as any)?.data?._node_env !== 'production';

  // Initialise shared currency formatter from store settings
  useEffect(() => {
    const currency = (configData as any)?.data?.data?.store_currency;
    if (currency) initCurrencyFromSettings(currency);
  }, [configData]);

  // Close mobile sidebar on route change
  useEffect(() => {
    setMobileSidebarOpen(false);
  }, [location.pathname, setMobileSidebarOpen]);

  // Global keyboard shortcuts
  const handleGlobalKeys = useCallback((e: KeyboardEvent) => {
    // Don't trigger shortcuts when typing in inputs or contentEditable elements
    const target = e.target as HTMLElement;
    const tag = target?.tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target?.isContentEditable) return;

    switch (e.key) {
      case 'F2': e.preventDefault(); navigate('/pos'); break;
      case 'F3': e.preventDefault(); navigate('/customers/new'); break;
      case 'F4': e.preventDefault(); navigate('/tickets'); break;
      case 'F6': e.preventDefault(); setCommandPaletteOpen(true); break;
      case '?': if (!e.ctrlKey && !e.metaKey) { setShortcutsPanelOpen(true); } break;
    }
  }, [navigate, setCommandPaletteOpen, setShortcutsPanelOpen]);

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
        style={{ '--dev-banner-h': isDev ? '28px' : '0px' } as React.CSSProperties}
      >
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
        {isDev && (
          <div className="relative z-0 flex items-center justify-center gap-2 bg-red-600 px-4 py-1.5 text-xs font-semibold text-white">
            <AlertTriangle className="h-3.5 w-3.5" />
            DEVELOPMENT MODE — NOT SECURE FOR PRODUCTION
          </div>
        )}
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
    </div>
  );
}
