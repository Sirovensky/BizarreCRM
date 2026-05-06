import { Routes, Route, Navigate, useNavigate } from 'react-router-dom';
import { lazy, Suspense, useEffect } from 'react';
import type { ComponentType, ReactNode } from 'react';
import { DashboardShell } from '@/components/layout/DashboardShell';
import { useAuthStore } from '@/stores/authStore';
import { useServerStore } from '@/stores/serverStore';
import toast from 'react-hot-toast';

const LoginPage = lazyNamed(() => import('@/pages/LoginPage'), 'LoginPage');
const OverviewPage = lazyNamed(() => import('@/pages/OverviewPage'), 'OverviewPage');
const ServerControlPage = lazyNamed(() => import('@/pages/ServerControlPage'), 'ServerControlPage');
const TenantsPage = lazyNamed(() => import('@/pages/TenantsPage'), 'TenantsPage');
const BackupPage = lazyNamed(() => import('@/pages/BackupPage'), 'BackupPage');
const CrashMonitorPage = lazyNamed(() => import('@/pages/CrashMonitorPage'), 'CrashMonitorPage');
const UpdatesPage = lazyNamed(() => import('@/pages/UpdatesPage'), 'UpdatesPage');
const ActivityPage = lazyNamed(() => import('@/pages/ActivityPage'), 'ActivityPage');
const AdminToolsPage = lazyNamed(() => import('@/pages/AdminToolsPage'), 'AdminToolsPage');
const LogsPage = lazyNamed(() => import('@/pages/LogsPage'), 'LogsPage');
const DiagnosticsPage = lazyNamed(() => import('@/pages/DiagnosticsPage'), 'DiagnosticsPage');
const SettingsPage = lazyNamed(() => import('@/pages/SettingsPage'), 'SettingsPage');

type LazyImport<TExport extends string> = Promise<Record<TExport, ComponentType>>;

function lazyNamed<TExport extends string>(
  loader: () => LazyImport<TExport>,
  exportName: TExport,
) {
  return lazy(async () => {
    const module = await loader();
    return { default: module[exportName] };
  });
}

function PageLoadingFallback({ variant = 'page' }: { variant?: 'page' | 'login' }) {
  const isLogin = variant === 'login';

  return (
    <div
      role="status"
      aria-live="polite"
      className={
        isLogin
          ? 'flex min-h-screen items-center justify-center bg-surface-950 p-6'
          : 'min-h-[24rem] w-full rounded-lg border border-surface-800 bg-surface-900/30 p-4'
      }
    >
      <div className={isLogin ? 'w-full max-w-sm' : 'w-full'}>
        <div className="flex items-center gap-3">
          <span
            className="h-4 w-4 animate-spin rounded-full border-2 border-surface-700 border-t-accent-400"
            aria-hidden="true"
          />
          <span className="text-sm font-medium text-surface-300">Loading dashboard page...</span>
        </div>
        <div className="mt-5 space-y-3" aria-hidden="true">
          <div className="h-8 w-2/5 rounded bg-surface-800/80" />
          <div className="h-24 rounded bg-surface-800/50" />
          <div className="grid gap-3 md:grid-cols-3">
            <div className="h-20 rounded bg-surface-800/40" />
            <div className="h-20 rounded bg-surface-800/40" />
            <div className="h-20 rounded bg-surface-800/40" />
          </div>
        </div>
      </div>
    </div>
  );
}

function LazyPage({ children, variant }: { children: ReactNode; variant?: 'page' | 'login' }) {
  return <Suspense fallback={<PageLoadingFallback variant={variant} />}>{children}</Suspense>;
}

function ProtectedRoute({ children }: { children: ReactNode }) {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }
  return <>{children}</>;
}

/**
 * DASH-ELEC-091 (Fixer-C24 2026-04-25): multi-tenant-only routes are filtered
 * from the Sidebar but the routes themselves were unguarded — typing
 * `/#/tenants` reached the full page in single-tenant mode. Wrap each
 * multi-tenant page in this guard so a direct URL hit redirects to the
 * Overview with an explanatory toast.
 */
function MultiTenantRoute({ children }: { children: ReactNode }) {
  const stats = useServerStore((s) => s.stats);
  // While stats are loading we don't know yet — render children to avoid
  // a redirect flicker. Sidebar already hides the link in single-tenant
  // mode, so this guard only matters for direct URL entry.
  const blocked = !!stats && stats.multiTenant === false;
  useEffect(() => {
    if (blocked) {
      toast.error('That page is only available in multi-tenant mode.');
    }
  }, [blocked]);
  if (blocked) {
    return <Navigate to="/" replace />;
  }
  return <>{children}</>;
}

/**
 * AUDIT-MGT-010: Subscribe to the managementAuthNavigateLogin event emitted by
 * authStore when any page detects a 401-shaped IPC response. This is the
 * bridge between the store (module scope, no router access) and the router.
 */
function AuthExpiredRedirect() {
  const navigate = useNavigate();
  useEffect(() => {
    const handler = () => navigate('/login', { replace: true });
    window.addEventListener('managementAuthNavigateLogin', handler);
    return () => window.removeEventListener('managementAuthNavigateLogin', handler);
  }, [navigate]);
  return null;
}

export default function App() {
  return (
    <>
      <AuthExpiredRedirect />
      <Routes>
      <Route path="/login" element={<LazyPage variant="login"><LoginPage /></LazyPage>} />

      <Route
        element={
          <ProtectedRoute>
            <DashboardShell />
          </ProtectedRoute>
        }
      >
        <Route index element={<LazyPage><OverviewPage /></LazyPage>} />
        <Route path="tenants" element={<MultiTenantRoute><LazyPage><TenantsPage /></LazyPage></MultiTenantRoute>} />
        <Route path="server" element={<LazyPage><ServerControlPage /></LazyPage>} />
        <Route path="backups" element={<LazyPage><BackupPage /></LazyPage>} />
        <Route path="crashes" element={<LazyPage><CrashMonitorPage /></LazyPage>} />
        <Route path="updates" element={<LazyPage><UpdatesPage /></LazyPage>} />
        <Route path="activity" element={<MultiTenantRoute><LazyPage><ActivityPage /></LazyPage></MultiTenantRoute>} />
        {/* Direct deep links from notifications/banners still resolve. */}
        <Route path="audit" element={<Navigate to="/activity?tab=audit" replace />} />
        <Route path="alerts" element={<Navigate to="/activity?tab=alerts" replace />} />
        <Route path="sessions" element={<Navigate to="/activity?tab=sessions" replace />} />
        <Route path="tools" element={<MultiTenantRoute><LazyPage><AdminToolsPage /></LazyPage></MultiTenantRoute>} />
        <Route path="logs" element={<LazyPage><LogsPage /></LazyPage>} />
        <Route path="diagnostics" element={<MultiTenantRoute><LazyPage><DiagnosticsPage /></LazyPage></MultiTenantRoute>} />
        {/* Legacy /comms deep links (sidebar + toasts pre-rename) redirect to new tab. */}
        <Route path="comms" element={<Navigate to="/diagnostics?tab=notifications" replace />} />
        <Route path="settings" element={<LazyPage><SettingsPage /></LazyPage>} />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
    </>
  );
}
