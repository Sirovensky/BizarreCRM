import { Routes, Route, Navigate, useNavigate } from 'react-router-dom';
import { useEffect } from 'react';
import { DashboardShell } from '@/components/layout/DashboardShell';
import { LoginPage } from '@/pages/LoginPage';
import { OverviewPage } from '@/pages/OverviewPage';
import { ServerControlPage } from '@/pages/ServerControlPage';
import { TenantsPage } from '@/pages/TenantsPage';
import { BackupPage } from '@/pages/BackupPage';
import { CrashMonitorPage } from '@/pages/CrashMonitorPage';
import { UpdatesPage } from '@/pages/UpdatesPage';
// AuditLogPage / SecurityAlertsPage / SessionsPage are now rendered as tabs
// inside ActivityPage — imports removed to satisfy noUnusedLocals (DASH-ELEC-104).
import { SettingsPage } from '@/pages/SettingsPage';
import { AdminToolsPage } from '@/pages/AdminToolsPage';
import { LogsPage } from '@/pages/LogsPage';
import { ActivityPage } from '@/pages/ActivityPage';
import { DiagnosticsPage } from '@/pages/DiagnosticsPage';
import { useAuthStore } from '@/stores/authStore';
import { useServerStore } from '@/stores/serverStore';
import toast from 'react-hot-toast';

function ProtectedRoute({ children }: { children: React.ReactNode }) {
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
function MultiTenantRoute({ children }: { children: React.ReactNode }) {
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
      <Route path="/login" element={<LoginPage />} />

      <Route
        element={
          <ProtectedRoute>
            <DashboardShell />
          </ProtectedRoute>
        }
      >
        <Route index element={<OverviewPage />} />
        <Route path="tenants" element={<MultiTenantRoute><TenantsPage /></MultiTenantRoute>} />
        <Route path="server" element={<ServerControlPage />} />
        <Route path="backups" element={<BackupPage />} />
        <Route path="crashes" element={<CrashMonitorPage />} />
        <Route path="updates" element={<UpdatesPage />} />
        <Route path="activity" element={<MultiTenantRoute><ActivityPage /></MultiTenantRoute>} />
        {/* Direct deep links from notifications/banners still resolve. */}
        <Route path="audit" element={<Navigate to="/activity?tab=audit" replace />} />
        <Route path="alerts" element={<Navigate to="/activity?tab=alerts" replace />} />
        <Route path="sessions" element={<Navigate to="/activity?tab=sessions" replace />} />
        <Route path="tools" element={<MultiTenantRoute><AdminToolsPage /></MultiTenantRoute>} />
        <Route path="logs" element={<LogsPage />} />
        <Route path="diagnostics" element={<MultiTenantRoute><DiagnosticsPage /></MultiTenantRoute>} />
        {/* Legacy /comms deep links (sidebar + toasts pre-rename) redirect to new tab. */}
        <Route path="comms" element={<Navigate to="/diagnostics?tab=notifications" replace />} />
        <Route path="settings" element={<SettingsPage />} />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
    </>
  );
}
