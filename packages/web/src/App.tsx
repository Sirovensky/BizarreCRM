import { lazy, Suspense, useEffect, useState } from 'react';
import { Routes, Route, Navigate, useLocation, Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { useAuthStore } from './stores/authStore';
import { authApi, settingsApi } from './api/endpoints';
import { extractApiError } from './utils/apiError';
import { AppShell } from './components/layout/AppShell';
import { ErrorBoundary } from './components/ErrorBoundary';
import { PageErrorBoundary } from './components/shared/PageErrorBoundary';
import { SpotlightCoach } from './components/onboarding/SpotlightCoach';

// Lazy-loaded page imports (code splitting)
const LoginPage = lazy(() => import('./pages/auth/LoginPage').then(m => ({ default: m.LoginPage })));
const ResetPasswordPage = lazy(() => import('./pages/auth/ResetPasswordPage').then(m => ({ default: m.ResetPasswordPage })));
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
// Inventory enrichment pages (criticalaudit.md §48).
const StocktakePage = lazy(() => import('./pages/inventory/StocktakePage').then(m => ({ default: m.StocktakePage })));
const BinLocationsPage = lazy(() => import('./pages/inventory/BinLocationsPage').then(m => ({ default: m.BinLocationsPage })));
const AutoReorderPage = lazy(() => import('./pages/inventory/AutoReorderPage').then(m => ({ default: m.AutoReorderPage })));
const SerialNumbersPage = lazy(() => import('./pages/inventory/SerialNumbersPage').then(m => ({ default: m.SerialNumbersPage })));
const ShrinkagePage = lazy(() => import('./pages/inventory/ShrinkagePage').then(m => ({ default: m.ShrinkagePage })));
const AbcAnalysisPage = lazy(() => import('./pages/inventory/AbcAnalysisPage').then(m => ({ default: m.AbcAnalysisPage })));
const InventoryAgePage = lazy(() => import('./pages/inventory/InventoryAgePage').then(m => ({ default: m.InventoryAgePage })));
const MassLabelPrintPage = lazy(() => import('./pages/inventory/MassLabelPrintPage').then(m => ({ default: m.MassLabelPrintPage })));
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
// Billing / Money Flow enrichment pages (criticalaudit.md §52).
const PaymentLinksPage = lazy(() => import('./pages/billing/PaymentLinksPage').then(m => ({ default: m.PaymentLinksPage })));
const DunningPage = lazy(() => import('./pages/billing/DunningPage').then(m => ({ default: m.DunningPage })));
const AgingReportPage = lazy(() => import('./pages/billing/AgingReportPage').then(m => ({ default: m.AgingReportPage })));
const CustomerPayPage = lazy(() => import('./pages/billing/CustomerPayPage').then(m => ({ default: m.CustomerPayPage })));
// Team management pages (criticalaudit.md §53).
const MyQueuePage = lazy(() => import('./pages/team/MyQueuePage').then(m => ({ default: m.MyQueuePage })));
const ShiftSchedulePage = lazy(() => import('./pages/team/ShiftSchedulePage').then(m => ({ default: m.ShiftSchedulePage })));
const TeamLeaderboardPage = lazy(() => import('./pages/team/TeamLeaderboardPage').then(m => ({ default: m.TeamLeaderboardPage })));
const RolesMatrixPage = lazy(() => import('./pages/team/RolesMatrixPage').then(m => ({ default: m.RolesMatrixPage })));
const TeamChatPage = lazy(() => import('./pages/team/TeamChatPage').then(m => ({ default: m.TeamChatPage })));
const PerformanceReviewsPage = lazy(() => import('./pages/team/PerformanceReviewsPage').then(m => ({ default: m.PerformanceReviewsPage })));
const GoalsPage = lazy(() => import('./pages/team/GoalsPage').then(m => ({ default: m.GoalsPage })));
// Marketing / Growth enrichment pages (§54).
const CampaignsPage = lazy(() => import('./pages/marketing/CampaignsPage').then(m => ({ default: m.CampaignsPage })));
const SegmentsPage = lazy(() => import('./pages/marketing/SegmentsPage').then(m => ({ default: m.SegmentsPage })));
const NpsTrendPage = lazy(() => import('./pages/marketing/NpsTrendPage').then(m => ({ default: m.NpsTrendPage })));
const ReferralsDashboard = lazy(() => import('./pages/marketing/ReferralsDashboard').then(m => ({ default: m.ReferralsDashboard })));
// Gift Cards (§ gift-cards orphan UI).
const GiftCardsListPage = lazy(() => import('./pages/gift-cards/GiftCardsListPage').then(m => ({ default: m.GiftCardsListPage })));
const GiftCardDetailPage = lazy(() => import('./pages/gift-cards/GiftCardDetailPage').then(m => ({ default: m.GiftCardDetailPage })));
// Memberships / Subscriptions admin list (§ subscriptions orphan UI).
const SubscriptionsListPage = lazy(() => import('./pages/subscriptions/SubscriptionsListPage').then(m => ({ default: m.SubscriptionsListPage })));
// Loaner devices
const LoanersPage = lazy(() => import('./pages/loaners/LoanersPage').then(m => ({ default: m.LoanersPage })));
// Automations standalone page
const AutomationsListPage = lazy(() => import('./pages/automations/AutomationsListPage').then(m => ({ default: m.AutomationsListPage })));
// Super-admin tenant management
const TenantsListPage = lazy(() => import('./pages/super-admin/TenantsListPage').then(m => ({ default: m.TenantsListPage })));
// Voice calls list
const VoiceCallsListPage = lazy(() => import('./pages/voice/VoiceCallsListPage').then(m => ({ default: m.VoiceCallsListPage })));

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
  const { data: setupData, isLoading: setupLoading, isError: setupError, error: setupErrorObj, refetch: refetchSetup } = useQuery<
    { data: { success: boolean; data: { setup_completed: boolean; store_name: string | null; wizard_completed: string | null } } }
  >({
    queryKey: ['setup-status'],
    queryFn: () => settingsApi.getSetupStatus(),
    staleTime: 30_000,
    enabled: isAuthenticated,
    retry: 1,
  });

  // AUDIT-WEB-011: if setup-status fails (server unreachable) don't spin
  // forever. Previously we silently redirected to /login which looked like
  // an infinite-loop post-2FA to the user because the login page would
  // immediately succeed again and ProtectedRoute would retry the failing
  // setup-status query. Surface the actual error code + request_id with
  // a retry button so the operator can fix the underlying issue (origin
  // guard, tenant context, rate limit) instead of bouncing between login
  // and loading screens.
  if (isLoading || (setupLoading && !setupError)) return <LoadingScreen />;
  if (setupError && !setupData) {
    return <SetupFailedScreen error={setupErrorObj} onRetry={() => refetchSetup()} />;
  }
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

/**
 * Shown when the mount-time /settings/setup-status query fails. Replaces the
 * old silent `<Navigate to="/login">` which caused an infinite login↔loading
 * loop when the failure was persistent (origin guard, tenant-context, rate
 * limit, offline server). Surface the exact server code + request id so the
 * user can send a support ticket with a traceable reference instead of a
 * screenshot of a blank loading spinner.
 */
function SetupFailedScreen({ error, onRetry }: { error: unknown; onRetry: () => void }) {
  const { code, requestId, message, status } = extractApiError(error);
  return (
    <div className="flex h-screen items-center justify-center bg-white dark:bg-surface-950 px-4">
      <div className="max-w-md w-full flex flex-col items-start gap-4 p-6 rounded-lg border border-surface-200 dark:border-surface-800 bg-surface-50 dark:bg-surface-900">
        <div>
          <h1 className="text-lg font-semibold text-surface-900 dark:text-surface-100">Unable to load the app</h1>
          <p className="mt-1 text-sm text-surface-600 dark:text-surface-400">{message}</p>
        </div>
        <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs font-mono text-surface-500 dark:text-surface-400">
          {status !== null && (
            <>
              <dt className="text-surface-400">status</dt>
              <dd>{status}</dd>
            </>
          )}
          {code && (
            <>
              <dt className="text-surface-400">code</dt>
              <dd>{code}</dd>
            </>
          )}
          {requestId && (
            <>
              <dt className="text-surface-400">ref</dt>
              <dd className="break-all">{requestId}</dd>
            </>
          )}
        </dl>
        <div className="flex items-center gap-2 mt-2">
          <button
            onClick={onRetry}
            className="px-3 py-1.5 text-sm font-medium text-white bg-primary-600 hover:bg-primary-700 rounded"
          >
            Retry
          </button>
          <button
            onClick={() => { window.location.href = '/login'; }}
            className="px-3 py-1.5 text-sm text-surface-700 dark:text-surface-300 border border-surface-300 dark:border-surface-700 rounded hover:bg-surface-100 dark:hover:bg-surface-800"
          >
            Sign out
          </button>
        </div>
      </div>
    </div>
  );
}

// Lazy-load landing + signup pages (code-split — never loaded on tenant subdomains)
const LandingPage = lazy(() => import('./pages/landing/LandingPage'));
const SignupPage = lazy(() => import('./pages/signup/SignupPage').then(m => ({ default: m.SignupPage })));

// Detect if we're on the bare domain (no tenant subdomain)
function isBareHostname(): boolean {
  const host = window.location.hostname; // e.g. "localhost", "example.com", "shop.example.com"
  // Bare domain: localhost, example.com, or an IP address
  if (host === 'localhost' || host === '127.0.0.1') return true;
  // Any IPv4 address (LAN, loopback, etc.) — never a tenant subdomain
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) return true;
  // "bizarreelectronics.localhost" = tenant subdomain in dev (2 parts but NOT bare)
  if (host.endsWith('.localhost')) return false;
  // If the host has no subdomain (only one dot: "example.com")
  const parts = host.split('.');
  if (parts.length <= 2) return true; // "example.com" = 2 parts = bare domain
  // "www.example.com" = still bare domain
  if (parts[0] === 'www' && parts.length === 3) return true;
  // "shop.example.com" = 3 parts with non-www prefix = tenant subdomain
  return false;
}

export default function App() {
  const { checkAuth, isLoading } = useAuthStore();
  const bareHostname = useState(() => isBareHostname())[0];
  // Server-driven tenancy mode. `undefined` = not yet known; `true` = bare
  // hostname should render the SaaS landing + signup flow; `false` = single-
  // tenant local server, bare hostname routes straight to /login (which
  // handles the first-run wizard when no users exist yet).
  const [showLanding, setShowLanding] = useState<boolean | undefined>(
    bareHostname ? undefined : false,
  );

  useEffect(() => {
    // Tenant subdomain — this is a tenant CRM, run the normal auth check.
    if (!bareHostname) {
      checkAuth();
      return;
    }

    // Bare hostname: ask the server which mode it's in. In multi-tenant mode
    // the landing page is correct. In single-tenant mode there is no landing —
    // the first visit to localhost must drop the user at the first-run wizard.
    let cancelled = false;
    authApi
      .setupStatus()
      .then((res) => {
        if (cancelled) return;
        const multi = res.data?.data?.isMultiTenant === true;
        setShowLanding(multi);
        if (!multi) {
          // Single-tenant mode: flush isLoading and let the CRM routes render.
          // The LoginPage effect picks up `needsSetup + isMultiTenant=false`
          // and shows the full first-run form automatically.
          useAuthStore.setState({ isLoading: false });
          checkAuth();
        } else {
          // Multi-tenant landing path stays as-is: no CRM auth check needed.
          useAuthStore.setState({ isLoading: false });
        }
      })
      .catch(() => {
        if (cancelled) return;
        // If the status call fails, err on the side of "landing" so
        // production SaaS traffic isn't routed into a broken CRM shell.
        setShowLanding(true);
        useAuthStore.setState({ isLoading: false });
      });
    return () => {
      cancelled = true;
    };
  }, [checkAuth, bareHostname]);

  // Waiting on the single-tenant vs multi-tenant decision before picking a
  // route tree — brief splash instead of flashing the wrong shell.
  if (showLanding === undefined) return <LoadingScreen />;

  // Bare domain AND multi-tenant — landing page + signup, completely
  // separate from CRM.
  if (showLanding) {
    return (
      <Suspense fallback={<LoadingScreen />}>
        <Routes>
          <Route path="/signup" element={<SignupPage />} />
          <Route path="/reset-password/:token" element={<ResetPasswordPage />} />
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
        <Route path="/reset-password/:token" element={<ResetPasswordPage />} />
        <Route path="/setup/:token" element={<LoginPage />} />
        <Route path="/setup" element={<ProtectedRoute><SetupPage /></ProtectedRoute>} />
        <Route path="/tv" element={<PageErrorBoundary><TvDisplayPage /></PageErrorBoundary>} />
        <Route path="/photo-capture/:ticketId/:deviceId" element={<PageErrorBoundary><PhotoCapturePage /></PageErrorBoundary>} />
        <Route path="/print/ticket/:id" element={<PrintPage />} />
        <Route path="/track" element={<TrackingPage />} />
        <Route path="/track/:orderId" element={<TrackingPage />} />
        <Route path="/customer-portal" element={<CustomerPortalPage />} />
        <Route path="/customer-portal/*" element={<CustomerPortalPage />} />
        {/* Public customer pay page — no auth, token validates server-side (§52). */}
        <Route path="/pay/:token" element={<CustomerPayPage />} />
        <Route
          path="/*"
          element={
            <ProtectedRoute>
              <AppShell>
                {/* SpotlightCoach is mounted globally so it persists across
                    page navigation. It reads the URL itself and renders
                    conditionally only when ?tutorial=... is present. */}
                <SpotlightCoach />
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
                    {/* Enrichment pages — MUST be registered before /inventory/:id
                        so the detail-page catch-all doesn't shadow them. */}
                    <Route path="/inventory/stocktake" element={<StocktakePage />} />
                    <Route path="/inventory/bin-locations" element={<BinLocationsPage />} />
                    <Route path="/inventory/auto-reorder" element={<AutoReorderPage />} />
                    <Route path="/inventory/serials" element={<SerialNumbersPage />} />
                    <Route path="/inventory/shrinkage" element={<ShrinkagePage />} />
                    <Route path="/inventory/abc-analysis" element={<AbcAnalysisPage />} />
                    <Route path="/inventory/age-report" element={<InventoryAgePage />} />
                    <Route path="/inventory/labels" element={<MassLabelPrintPage />} />
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
                    {/* Billing / Money Flow enrichment (§52). */}
                    <Route path="/billing/payment-links" element={<PaymentLinksPage />} />
                    <Route path="/billing/dunning" element={<DunningPage />} />
                    <Route path="/billing/aging" element={<AgingReportPage />} />
                    {/* Team management (§53). */}
                    <Route path="/team/my-queue" element={<MyQueuePage />} />
                    <Route path="/team/shifts" element={<ShiftSchedulePage />} />
                    <Route path="/team/leaderboard" element={<TeamLeaderboardPage />} />
                    <Route path="/team/roles" element={<RolesMatrixPage />} />
                    <Route path="/team/chat" element={<TeamChatPage />} />
                    <Route path="/team/reviews" element={<PerformanceReviewsPage />} />
                    <Route path="/team/goals" element={<GoalsPage />} />
                    {/* Gift Cards (§ orphan). */}
                    <Route path="/gift-cards" element={<GiftCardsListPage />} />
                    <Route path="/gift-cards/:id" element={<GiftCardDetailPage />} />
                    {/* Memberships / Subscriptions admin list (§ orphan). */}
                    <Route path="/subscriptions" element={<SubscriptionsListPage />} />
                    {/* Loaner device management. */}
                    <Route path="/loaners" element={<LoanersPage />} />
                    {/* Automations standalone page. */}
                    <Route path="/automations" element={<AutomationsListPage />} />
                    {/* Super-admin tenant management. */}
                    <Route path="/super-admin/tenants" element={<TenantsListPage />} />
                    {/* Voice calls list. */}
                    <Route path="/voice" element={<VoiceCallsListPage />} />
                    {/* Marketing / Growth enrichment (§54). */}
                    <Route path="/marketing/campaigns" element={<CampaignsPage />} />
                    <Route path="/marketing/segments" element={<SegmentsPage />} />
                    <Route path="/marketing/nps-trend" element={<NpsTrendPage />} />
                    <Route path="/marketing/referrals" element={<ReferralsDashboard />} />
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
