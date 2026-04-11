import { lazy, Suspense, useEffect, useState } from 'react';
import { Routes, Route, Navigate, useLocation, Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { useAuthStore } from './stores/authStore';
import { settingsApi } from './api/endpoints';
import { AppShell } from './components/layout/AppShell';
import { ErrorBoundary } from './components/ErrorBoundary';
import { PageErrorBoundary } from './components/shared/PageErrorBoundary';

// Lazy-loaded page imports (code splitting)
const LoginPage = lazy(() => import('./pages/auth/LoginPage').then(m => ({ default: m.LoginPage })));
const SetupPage = lazy(() => import('./pages/setup/SetupPage').then(m => ({ default: m.SetupPage })));
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
const LeadPipelinePage = lazy(() => import('./pages/leads/LeadPipelinePage').then(m => ({ default: m.LeadPipelinePage })));
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
const CustomerPortalPage = lazy(() => import('./pages/portal/CustomerPortalPage').then(m => ({ default: m.CustomerPortalPage })));

function NotFoundPage() {
  return (
    <div className="flex flex-col items-center justify-center h-[60vh] text-center">
      <h1 className="text-4xl font-bold text-gray-800 mb-2">404</h1>
      <p className="text-lg text-gray-600 mb-6">Page not found</p>
      <Link
        to="/"
        className="px-4 py-2 bg-primary-600 text-white rounded-lg hover:bg-primary-700 transition-colors"
      >
        Back to Dashboard
      </Link>
    </div>
  );
}

function PageLoader() {
  return (
    <div className="flex items-center justify-center h-[50vh]">
      <div className="h-8 w-8 border-4 border-primary-200 border-t-primary-600 rounded-full animate-spin" />
    </div>
  );
}

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { isAuthenticated, isLoading } = useAuthStore();
  const location = useLocation();
  const { data: setupData, isLoading: setupLoading } = useQuery<
    { data: { success: boolean; data: { setup_completed: boolean; store_name: string | null; wizard_completed: string | null } } }
  >({
    queryKey: ['setup-status'],
    queryFn: () => settingsApi.getSetupStatus(),
    staleTime: 30_000,
    enabled: isAuthenticated,
  });

  if (isLoading || setupLoading) return <LoadingScreen />;
  if (!isAuthenticated) return <Navigate to="/login" replace />;

  const setupCompleted = setupData?.data?.data?.setup_completed;
  const wizardCompleted = setupData?.data?.data?.wizard_completed;

  // Gate 1: setup_completed=false -> send to /setup (existing behavior, for tenants that
  // have no admin user yet; provisionTenant sets this to true for the password-provided
  // signup path, so in practice this gate mostly doesn't fire for self-serve signups).
  if (setupCompleted === false && !location.pathname.startsWith('/setup')) {
    return <Navigate to="/setup" replace />;
  }

  // Gate 2 (NEW): setup_completed=true but wizard_completed is unset -> send to /setup.
  // Valid wizard_completed values are 'true', 'skipped', or 'grandfathered' (set on
  // startup for pre-feature tenants). Any other falsy value (null / undefined / empty
  // string) means this is a brand-new post-feature tenant who hasn't been through the
  // wizard yet.
  const wizardDone =
    wizardCompleted === 'true' ||
    wizardCompleted === 'skipped' ||
    wizardCompleted === 'grandfathered';
  if (
    setupCompleted === true &&
    !wizardDone &&
    !location.pathname.startsWith('/setup')
  ) {
    return <Navigate to="/setup" replace />;
  }

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

// Lazy-load landing + signup pages (code-split — never loaded on tenant subdomains)
const LandingPage = lazy(() => import('./pages/landing/LandingPage'));
const SignupPage = lazy(() => import('./pages/signup/SignupPage').then(m => ({ default: m.SignupPage })));

// Detect if we're on the bare domain (no tenant subdomain)
function isBareHostname(): boolean {
  const host = window.location.hostname; // e.g. "localhost", "bizarrecrm.com", "shop.bizarrecrm.com"
  // Bare domain: localhost, bizarrecrm.com, or an IP address
  if (host === 'localhost' || host === '127.0.0.1') return true;
  // "bizarreelectronics.localhost" = tenant subdomain in dev (2 parts but NOT bare)
  if (host.endsWith('.localhost')) return false;
  // If the host has no subdomain (only one dot: "bizarrecrm.com")
  const parts = host.split('.');
  if (parts.length <= 2) return true; // "bizarrecrm.com" = 2 parts = bare domain
  // "www.bizarrecrm.com" = still bare domain
  if (parts[0] === 'www' && parts.length === 3) return true;
  // "shop.bizarrecrm.com" = 3 parts with non-www prefix = tenant subdomain
  return false;
}

export default function App() {
  const { checkAuth, isLoading } = useAuthStore();
  const [showLanding] = useState(() => isBareHostname());

  useEffect(() => {
    // Skip auth check on landing page — no CRM needed. Still need to flush the
    // default `isLoading: true` state so the landing route doesn't get stuck
    // on a loading screen forever (W4 fix).
    if (showLanding) {
      useAuthStore.setState({ isLoading: false });
      return;
    }
    checkAuth();
  }, [checkAuth, showLanding]);

  // Bare domain — landing page + signup, completely separate from CRM
  if (showLanding) {
    return (
      <Suspense fallback={<LoadingScreen />}>
        <Routes>
          <Route path="/signup" element={<SignupPage />} />
          <Route path="*" element={<LandingPage />} />
        </Routes>
      </Suspense>
    );
  }

  // Block initial render until checkAuth() resolves so ProtectedRoute can
  // trust the isAuthenticated flag. The ProtectedRoute guard also re-checks
  // isLoading — both layers keep the redirect-to-login logic correct under
  // a fast page refresh (W4 fix).
  if (isLoading) return <LoadingScreen />;

  return (
    <ErrorBoundary>
    <Suspense fallback={<PageLoader />}>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="/setup/:token" element={<LoginPage />} />
        <Route path="/setup" element={<ProtectedRoute><SetupPage /></ProtectedRoute>} />
        <Route path="/tv" element={<PageErrorBoundary><TvDisplayPage /></PageErrorBoundary>} />
        <Route path="/photo-capture/:ticketId/:deviceId" element={<PageErrorBoundary><PhotoCapturePage /></PageErrorBoundary>} />
        <Route path="/print/ticket/:id" element={<PrintPage />} />
        <Route path="/track" element={<TrackingPage />} />
        <Route path="/track/:orderId" element={<TrackingPage />} />
        <Route path="/customer-portal" element={<CustomerPortalPage />} />
        <Route path="/customer-portal/*" element={<CustomerPortalPage />} />
        <Route
          path="/*"
          element={
            <ProtectedRoute>
              <AppShell>
                <PageErrorBoundary>
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
                    <Route path="/pipeline" element={<LeadPipelinePage />} />
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
                    <Route path="*" element={<NotFoundPage />} />
                  </Routes>
                </Suspense>
                </PageErrorBoundary>
              </AppShell>
            </ProtectedRoute>
          }
        />
      </Routes>
    </Suspense>
    </ErrorBoundary>
  );
}
