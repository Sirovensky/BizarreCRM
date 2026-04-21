import { Outlet } from 'react-router-dom';
import { Header } from './Header';
import { Sidebar } from './Sidebar';
import { PageErrorBoundary } from '@/components/shared/ErrorBoundary';
import { useServerHealth } from '@/hooks/useServerHealth';
import { BannerCertWarning } from '@/components/BannerCertWarning';
import { BannerTagVerifyWarning } from '@/components/BannerTagVerifyWarning';
import { CommandPalette } from '@/components/CommandPalette';
import { KeyboardShortcutsHelp } from '@/components/KeyboardShortcutsHelp';

export function DashboardShell() {
  // Start health polling when the shell mounts (user is authenticated)
  useServerHealth();

  return (
    <div className="flex flex-col h-screen overflow-hidden">
      {/* AUDIT-MGT-006: visible warning when TLS cert pinning is disabled */}
      <BannerCertWarning />
      {/* AUDIT-MGT-018: visible warning when signed-tag verification bypass is active */}
      <BannerTagVerifyWarning />
      {/* Global Cmd/Ctrl+K / `/` command palette mounted once at the shell. */}
      <CommandPalette />
      {/* `?` opens keyboard shortcut help overlay. */}
      <KeyboardShortcutsHelp />
      <Header />
      <div className="flex flex-1 overflow-hidden">
        <Sidebar />
        <main className="flex-1 overflow-y-auto p-3 lg:p-5 xl:p-6">
          <PageErrorBoundary>
            <Outlet />
          </PageErrorBoundary>
        </main>
      </div>
    </div>
  );
}
