import { Outlet, useLocation } from 'react-router-dom';
import { useRef, useEffect } from 'react';
import { Header } from './Header';
import { Sidebar } from './Sidebar';
import { StatusFooter } from './StatusFooter';
import { PageErrorBoundary } from '@/components/shared/ErrorBoundary';
import { useServerHealth } from '@/hooks/useServerHealth';
import { BannerCertWarning } from '@/components/BannerCertWarning';
import { BannerTagVerifyWarning } from '@/components/BannerTagVerifyWarning';
import { CommandPalette } from '@/components/CommandPalette';
import { KeyboardShortcutsHelp } from '@/components/KeyboardShortcutsHelp';

export function DashboardShell() {
  // Start health polling when the shell mounts (user is authenticated)
  useServerHealth();
  const { pathname } = useLocation();
  const mainRef = useRef<HTMLElement>(null);

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
      {/* DASH-ELEC-015: per-section error boundaries so a render crash in one
          shell section doesn't take down the entire layout. */}
      <PageErrorBoundary fallbackTitle="Header failed to render">
        <Header />
      </PageErrorBoundary>
      <div className="flex flex-1 overflow-hidden">
        <PageErrorBoundary fallbackTitle="Sidebar failed to render">
          <Sidebar />
        </PageErrorBoundary>
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
      <PageErrorBoundary fallbackTitle="Status bar failed to render">
        <StatusFooter />
      </PageErrorBoundary>
    </div>
  );
}
