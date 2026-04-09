import { Outlet } from 'react-router-dom';
import { Header } from './Header';
import { Sidebar } from './Sidebar';
import { PageErrorBoundary } from '@/components/shared/ErrorBoundary';
import { useServerHealth } from '@/hooks/useServerHealth';

export function DashboardShell() {
  // Start health polling when the shell mounts (user is authenticated)
  useServerHealth();

  return (
    <div className="flex flex-col h-screen overflow-hidden">
      <Header />
      <div className="flex flex-1 overflow-hidden">
        <Sidebar />
        <main className="flex-1 overflow-y-auto p-6">
          <PageErrorBoundary>
            <Outlet />
          </PageErrorBoundary>
        </main>
      </div>
    </div>
  );
}
