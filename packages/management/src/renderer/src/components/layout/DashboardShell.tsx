import { Outlet, useLocation } from 'react-router-dom';
import { useRef, useEffect } from 'react';
import { AlertTriangle } from 'lucide-react';
import { Header } from './Header';
import { Sidebar } from './Sidebar';
import { StatusFooter } from './StatusFooter';
import { PageErrorBoundary } from '@/components/shared/ErrorBoundary';
import { useServerHealth } from '@/hooks/useServerHealth';
import { useServerStore } from '@/stores/serverStore';
import { BannerCertWarning } from '@/components/BannerCertWarning';
import { BannerTagVerifyWarning } from '@/components/BannerTagVerifyWarning';
import { CommandPalette } from '@/components/CommandPalette';
import { KeyboardShortcutsHelp } from '@/components/KeyboardShortcutsHelp';

export function DashboardShell() {
  // Start health polling when the shell mounts (user is authenticated)
  useServerHealth();
  const { pathname } = useLocation();
  const mainRef = useRef<HTMLElement>(null);
  // DASH-ELEC-233: global offline banner — was only in OverviewPage so
  // navigating away silently hid the indicator.
  const isOnline = useServerStore((s) => s.isOnline);
  const lastError = useServerStore((s) => s.lastError);

  // DASH-ELEC-121: reset scroll position on route change
  // DASH-ELEC-092: move focus to main content on route change for keyboard/SR users
  useEffect(() => {
    mainRef.current?.scrollTo(0, 0);
    mainRef.current?.focus();
  }, [pathname]);

  return (
    <div className="flex flex-col h-screen overflow-hidden">
      {/* DASH-ELEC-092: skip-nav link for keyboard users */}
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:px-3 focus:py-1.5 focus:rounded focus:bg-accent-500 focus:text-white focus:text-sm focus:font-medium"
      >
        Skip to main content
      </a>
      {/* AUDIT-MGT-006: visible warning when TLS cert pinning is disabled */}
      <BannerCertWarning />
      {/* AUDIT-MGT-018: visible warning when signed-tag verification bypass is active */}
      <BannerTagVerifyWarning />
      {/* Global Cmd/Ctrl+K / `/` command palette mounted once at the shell. */}
      <CommandPalette />
      {/* `?` opens keyboard shortcut help overlay. */}
      <KeyboardShortcutsHelp />
      <Header />
      {/* DASH-ELEC-233: offline banner in the shell so it appears on every page,
          not only when the operator happens to be on OverviewPage. */}
      {!isOnline && (
        <div
          role="alert"
          className="flex items-center gap-3 px-4 py-2 bg-red-950/40 border-b border-red-900/50"
        >
          <AlertTriangle className="w-4 h-4 text-red-400 flex-shrink-0" />
          <div>
            <span className="text-xs font-semibold text-red-300">Server Offline — </span>
            <span className="text-xs text-red-400">{lastError ?? 'Unable to reach the CRM server'}</span>
          </div>
        </div>
      )}
      <div className="flex flex-1 overflow-hidden">
        <Sidebar />
        {/* DASH-ELEC-092: id + tabIndex=-1 so focus() works programmatically */}
        <main
          id="main-content"
          ref={mainRef}
          tabIndex={-1}
          aria-label="Main content"
          className="flex-1 overflow-y-auto p-3 lg:p-5 xl:p-6 outline-none"
        >
          <PageErrorBoundary key={pathname}>
            <Outlet />
          </PageErrorBoundary>
        </main>
      </div>
      <StatusFooter />
    </div>
  );
}
