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
import { AuditLogPage } from '@/pages/AuditLogPage';
import { SecurityAlertsPage } from '@/pages/SecurityAlertsPage';
import { SessionsPage } from '@/pages/SessionsPage';
import { SettingsPage } from '@/pages/SettingsPage';
import { AdminToolsPage } from '@/pages/AdminToolsPage';
import { LogsPage } from '@/pages/LogsPage';
import { useAuthStore } from '@/stores/authStore';

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
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
        <Route path="tenants" element={<TenantsPage />} />
        <Route path="server" element={<ServerControlPage />} />
        <Route path="backups" element={<BackupPage />} />
        <Route path="crashes" element={<CrashMonitorPage />} />
        <Route path="updates" element={<UpdatesPage />} />
        <Route path="audit" element={<AuditLogPage />} />
        <Route path="alerts" element={<SecurityAlertsPage />} />
        <Route path="sessions" element={<SessionsPage />} />
        <Route path="tools" element={<AdminToolsPage />} />
        <Route path="logs" element={<LogsPage />} />
        <Route path="settings" element={<SettingsPage />} />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
    </>
  );
}
