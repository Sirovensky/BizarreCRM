import { lazy, Suspense, useEffect } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuthStore } from './stores/authStore';
import { AppShell } from './components/layout/AppShell';

// Lazy-loaded page imports (code splitting)
const LoginPage = lazy(() => import('./pages/auth/LoginPage').then(m => ({ default: m.LoginPage })));
const DashboardPage = lazy(() => import('./pages/dashboard/DashboardPage').then(m => ({ default: m.DashboardPage })));
const TicketListPage = lazy(() => import('./pages/tickets/TicketListPage').then(m => ({ default: m.TicketListPage })));
const TicketDetailPage = lazy(() => import('./pages/tickets/TicketDetailPage').then(m => ({ default: m.TicketDetailPage })));
// const TicketWizard = lazy(() => import('./pages/tickets/TicketWizard').then(m => ({ default: m.TicketWizard })));
const CustomerListPage = lazy(() => import('./pages/customers/CustomerListPage').then(m => ({ default: m.CustomerListPage })));
const CustomerDetailPage = lazy(() => import('./pages/customers/CustomerDetailPage').then(m => ({ default: m.CustomerDetailPage })));
const CustomerCreatePage = lazy(() => import('./pages/customers/CustomerCreatePage').then(m => ({ default: m.CustomerCreatePage })));
const InventoryListPage = lazy(() => import('./pages/inventory/InventoryListPage').then(m => ({ default: m.InventoryListPage })));
const InventoryDetailPage = lazy(() => import('./pages/inventory/InventoryDetailPage').then(m => ({ default: m.InventoryDetailPage })));
const InventoryCreatePage = lazy(() => import('./pages/inventory/InventoryCreatePage').then(m => ({ default: m.InventoryCreatePage })));
const InvoiceListPage = lazy(() => import('./pages/invoices/InvoiceListPage').then(m => ({ default: m.InvoiceListPage })));
const InvoiceDetailPage = lazy(() => import('./pages/invoices/InvoiceDetailPage').then(m => ({ default: m.InvoiceDetailPage })));
const PhotoCapturePage = lazy(() => import('./pages/photo-capture/PhotoCapturePage').then(m => ({ default: m.PhotoCapturePage })));
const LeadListPage = lazy(() => import('./pages/leads/LeadListPage').then(m => ({ default: m.LeadListPage })));
const LeadDetailPage = lazy(() => import('./pages/leads/LeadDetailPage').then(m => ({ default: m.LeadDetailPage })));
const CalendarPage = lazy(() => import('./pages/leads/CalendarPage').then(m => ({ default: m.CalendarPage })));
const EstimateListPage = lazy(() => import('./pages/estimates/EstimateListPage').then(m => ({ default: m.EstimateListPage })));
const EstimateDetailPage = lazy(() => import('./pages/estimates/EstimateDetailPage').then(m => ({ default: m.EstimateDetailPage })));
// const PosPage = lazy(() => import('./pages/pos/PosPage').then(m => ({ default: m.PosPage })));
const UnifiedPosPage = lazy(() => import('./pages/unified-pos/UnifiedPosPage').then(m => ({ default: m.UnifiedPosPage })));
const ReportsPage = lazy(() => import('./pages/reports/ReportsPage').then(m => ({ default: m.ReportsPage })));
const ExpensesPage = lazy(() => import('./pages/expenses/ExpensesPage').then(m => ({ default: m.ExpensesPage })));
const PurchaseOrdersPage = lazy(() => import('./pages/inventory/PurchaseOrdersPage').then(m => ({ default: m.PurchaseOrdersPage })));
const CashRegisterPage = lazy(() => import('./pages/pos/CashRegisterPage').then(m => ({ default: m.CashRegisterPage })));
const CommunicationPage = lazy(() => import('./pages/communications/CommunicationPage').then(m => ({ default: m.CommunicationPage })));
const EmployeeListPage = lazy(() => import('./pages/employees/EmployeeListPage').then(m => ({ default: m.EmployeeListPage })));
const SettingsPage = lazy(() => import('./pages/settings/SettingsPage').then(m => ({ default: m.SettingsPage })));
const TvDisplayPage = lazy(() => import('./pages/tv/TvDisplayPage').then(m => ({ default: m.TvDisplayPage })));
const CatalogPage = lazy(() => import('./pages/catalog/CatalogPage').then(m => ({ default: m.CatalogPage })));
const PrintPage = lazy(() => import('./pages/print/PrintPage').then(m => ({ default: m.PrintPage })));
const TrackingPage = lazy(() => import('./pages/tracking/TrackingPage').then(m => ({ default: m.TrackingPage })));

function PageLoader() {
  return (
    <div className="flex items-center justify-center h-[50vh]">
      <div className="h-8 w-8 border-4 border-primary-200 border-t-primary-600 rounded-full animate-spin" />
    </div>
  );
}

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { isAuthenticated, isLoading } = useAuthStore();
  if (isLoading) return <LoadingScreen />;
  if (!isAuthenticated) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

function LoadingScreen() {
  return (
    <div className="flex h-screen items-center justify-center bg-white dark:bg-surface-950">
      <div className="flex flex-col items-center gap-4">
        <div className="h-10 w-10 animate-spin rounded-full border-4 border-primary-200 border-t-primary-600" />
        <p className="text-sm text-surface-500">Loading...</p>
      </div>
    </div>
  );
}

export default function App() {
  const { checkAuth, isLoading } = useAuthStore();

  useEffect(() => {
    checkAuth();
  }, [checkAuth]);

  if (isLoading) return <LoadingScreen />;

  return (
    <Suspense fallback={<PageLoader />}>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="/tv" element={<TvDisplayPage />} />
        <Route path="/photo-capture/:ticketId/:deviceId" element={<PhotoCapturePage />} />
        <Route path="/print/ticket/:id" element={<PrintPage />} />
        <Route path="/track" element={<TrackingPage />} />
        <Route path="/track/:orderId" element={<TrackingPage />} />
        <Route
          path="/*"
          element={
            <ProtectedRoute>
              <AppShell>
                <Suspense fallback={<PageLoader />}>
                  <Routes>
                    <Route path="/" element={<DashboardPage />} />
                    <Route path="/tickets" element={<TicketListPage />} />
                    <Route path="/tickets/new" element={<UnifiedPosPage />} />
                    <Route path="/tickets/:id" element={<TicketDetailPage />} />
                    <Route path="/customers" element={<CustomerListPage />} />
                    <Route path="/customers/new" element={<CustomerCreatePage />} />
                    <Route path="/customers/:id" element={<CustomerDetailPage />} />
                    <Route path="/inventory" element={<InventoryListPage />} />
                    <Route path="/inventory/new" element={<InventoryCreatePage />} />
                    <Route path="/inventory/:id" element={<InventoryDetailPage />} />
                    <Route path="/invoices" element={<InvoiceListPage />} />
                    <Route path="/invoices/:id" element={<InvoiceDetailPage />} />
                    <Route path="/checkin" element={<UnifiedPosPage />} />
                    <Route path="/leads" element={<LeadListPage />} />
                    <Route path="/leads/:id" element={<LeadDetailPage />} />
                    <Route path="/calendar" element={<CalendarPage />} />
                    <Route path="/estimates" element={<EstimateListPage />} />
                    <Route path="/estimates/:id" element={<EstimateDetailPage />} />
                    <Route path="/pos" element={<UnifiedPosPage />} />
                    <Route path="/reports" element={<ReportsPage />} />
                    <Route path="/expenses" element={<ExpensesPage />} />
                    <Route path="/purchase-orders" element={<PurchaseOrdersPage />} />
                    <Route path="/cash-register" element={<CashRegisterPage />} />
                    <Route path="/communications" element={<CommunicationPage />} />
                    <Route path="/employees" element={<EmployeeListPage />} />
                    <Route path="/settings/*" element={<SettingsPage />} />
                    <Route path="/catalog" element={<CatalogPage />} />
                    <Route path="*" element={<Navigate to="/" replace />} />
                  </Routes>
                </Suspense>
              </AppShell>
            </ProtectedRoute>
          }
        />
      </Routes>
    </Suspense>
  );
}
