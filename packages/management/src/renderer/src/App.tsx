import { Routes, Route, Navigate } from 'react-router-dom';
import { DashboardShell } from '@/components/layout/DashboardShell';
import { LoginPage } from '@/pages/LoginPage';
import { OverviewPage } from '@/pages/OverviewPage';
import { ServerControlPage } from '@/pages/ServerControlPage';
import { TenantsPage } from '@/pages/TenantsPage';
import { BackupPage } from '@/pages/BackupPage';
import { CrashMonitorPage } from '@/pages/CrashMonitorPage';
import { UpdatesPage } from '@/pages/UpdatesPage';
import { AuditLogPage } from '@/pages/AuditLogPage';
import { SessionsPage } from '@/pages/SessionsPage';
import { SettingsPage } from '@/pages/SettingsPage';
import { useAuthStore } from '@/stores/authStore';

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }
  return <>{children}</>;
}

export default function App() {
  return (
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
        <Route path="sessions" element={<SessionsPage />} />
        <Route path="settings" element={<SettingsPage />} />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
