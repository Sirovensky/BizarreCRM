package com.bizarreelectronics.crm.ui.navigation

import android.net.Uri
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.ripple
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.*
import androidx.navigation.navArgument
import androidx.navigation.navDeepLink
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.ui.screens.auth.BackupCodeRecoveryScreen
import com.bizarreelectronics.crm.ui.screens.auth.ForgotPasswordScreen
import com.bizarreelectronics.crm.ui.screens.auth.LoginScreen
import com.bizarreelectronics.crm.ui.screens.auth.SetupStatusGateScreen
import com.bizarreelectronics.crm.ui.screens.auth.ResetPasswordScreen
import com.bizarreelectronics.crm.ui.screens.dashboard.DashboardScreen
import com.bizarreelectronics.crm.ui.screens.tickets.TicketListScreen
import com.bizarreelectronics.crm.ui.screens.tickets.TicketDetailScreen
import com.bizarreelectronics.crm.ui.screens.customers.CustomerListScreen
import com.bizarreelectronics.crm.ui.screens.customers.CustomerDetailScreen
import com.bizarreelectronics.crm.ui.screens.inventory.InventoryListScreen
import com.bizarreelectronics.crm.ui.screens.invoices.InvoiceCreateScreen
import com.bizarreelectronics.crm.ui.screens.invoices.InvoiceDetailScreen
import com.bizarreelectronics.crm.ui.screens.invoices.InvoiceListScreen
import com.bizarreelectronics.crm.ui.screens.inventory.BarcodeScanScreen
import com.bizarreelectronics.crm.ui.screens.inventory.InventoryDetailScreen
import com.bizarreelectronics.crm.ui.screens.pos.CheckoutScreen
import com.bizarreelectronics.crm.ui.screens.pos.PosScreen
import com.bizarreelectronics.crm.ui.screens.pos.TicketSuccessScreen
import com.bizarreelectronics.crm.ui.screens.communications.SmsListScreen
import com.bizarreelectronics.crm.ui.screens.communications.SmsThreadScreen
import com.bizarreelectronics.crm.ui.screens.notifications.NotificationListScreen
import com.bizarreelectronics.crm.ui.screens.reports.ReportsScreen
import com.bizarreelectronics.crm.ui.screens.employees.ClockInOutScreen
import com.bizarreelectronics.crm.ui.screens.employees.EmployeeListScreen
import com.bizarreelectronics.crm.ui.screens.tickets.TicketDeviceEditScreen
import com.bizarreelectronics.crm.ui.screens.camera.PhotoCaptureScreen
import com.bizarreelectronics.crm.ui.screens.settings.ChangePasswordScreen
import com.bizarreelectronics.crm.ui.screens.settings.DiagnosticsScreen
import com.bizarreelectronics.crm.ui.screens.settings.LanguageScreen
import com.bizarreelectronics.crm.ui.screens.settings.NotificationSettingsScreen
import com.bizarreelectronics.crm.ui.screens.settings.ProfileScreen
import com.bizarreelectronics.crm.ui.screens.settings.SecurityScreen
import com.bizarreelectronics.crm.ui.screens.settings.SettingsScreen
import com.bizarreelectronics.crm.ui.screens.settings.SettingsViewModel
import com.bizarreelectronics.crm.ui.screens.settings.ThemeScreen
import com.bizarreelectronics.crm.ui.screens.settings.SwitchUserScreen
import com.bizarreelectronics.crm.ui.screens.search.GlobalSearchScreen
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.sync.SyncManager
import com.bizarreelectronics.crm.ui.components.ClockDriftBanner
import com.bizarreelectronics.crm.ui.components.RateLimitBanner
import com.bizarreelectronics.crm.ui.components.SessionTimeoutOverlay
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.OfflineBanner
import com.bizarreelectronics.crm.util.ClockDrift
import com.bizarreelectronics.crm.util.DeepLinkBus
import com.bizarreelectronics.crm.util.RateLimiter
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.util.SessionTimeout
import java.util.Locale
import javax.inject.Inject

sealed class Screen(val route: String) {
    data object Login : Screen("login")
    data object Dashboard : Screen("dashboard")
    data object Tickets : Screen("tickets")
    data object TicketDetail : Screen("tickets/{id}") {
        fun createRoute(id: Long) = "tickets/$id"
    }
    data object TicketCreate : Screen("ticket-create") {
        /**
         * CROSS47-seed: when launched from a customer detail, pre-seed the
         * wizard with that customer's id as an optional `customerId` query
         * arg. Nav route remains `ticket-create` (without the query string)
         * so existing call sites that don't care about seeding continue to
         * hit the same destination.
         */
        fun createRoute(customerId: Long? = null): String =
            if (customerId != null) "ticket-create?customerId=$customerId" else "ticket-create"
    }
    data object TicketDeviceEdit : Screen("tickets/{ticketId}/devices/{deviceId}") {
        fun createRoute(ticketId: Long, deviceId: Long) = "tickets/$ticketId/devices/$deviceId"
    }
    // AND-20260414-M1: photo capture / gallery upload screen for a ticket.
    // The PhotoCaptureScreen composable already existed under
    // ui/screens/camera/ but had no route and no entry point from ticket
    // detail, so technicians could not attach new repair photos even though
    // the API endpoint and viewmodel were wired. This route + an
    // `onAddPhotos` callback from TicketDetailScreen close that gap.
    //
    // bug:gallery-400 fix: route now carries `deviceId` because the server's
    // POST /:id/photos endpoint requires ticket_device_id in the body. The
    // caller (TicketDetailScreen) passes the first device's id when navigating.
    data object TicketPhotos : Screen("tickets/{ticketId}/photos/{deviceId}") {
        fun createRoute(ticketId: Long, deviceId: Long) = "tickets/$ticketId/photos/$deviceId"
    }
    data object Customers : Screen("customers")
    data object CustomerDetail : Screen("customers/{id}") {
        fun createRoute(id: Long) = "customers/$id"
    }
    data object CustomerCreate : Screen("customer-create")
    data object Inventory : Screen("inventory")
    data object InventoryDetail : Screen("inventory/{id}") {
        fun createRoute(id: Long) = "inventory/$id"
    }
    data object Invoices : Screen("invoices")
    data object InvoiceDetail : Screen("invoices/{id}") {
        fun createRoute(id: Long) = "invoices/$id"
    }
    data object InvoiceCreate : Screen("invoice-create")
    data object Pos : Screen("pos")
    data object Checkout : Screen("checkout/{ticketId}/{total}/{customerName}") {
        fun createRoute(ticketId: Long, total: Double, customerName: String): String {
            val encodedName = Uri.encode(customerName)
            val formattedTotal = String.format(Locale.US, "%.2f", total)
            return "checkout/$ticketId/$formattedTotal/$encodedName"
        }
    }
    data object TicketSuccess : Screen("ticket-success/{ticketId}") {
        fun createRoute(ticketId: Long, ticketOrderId: String? = null): String {
            val base = "ticket-success/$ticketId"
            return if (ticketOrderId != null) "$base?orderId=${Uri.encode(ticketOrderId)}" else base
        }
    }
    data object Messages : Screen("messages")
    data object SmsThread : Screen("messages/{phone}") {
        fun createRoute(phone: String) = "messages/${Uri.encode(phone)}"
    }
    data object Reports : Screen("reports")
    data object Employees : Screen("employees")
    data object EmployeeCreate : Screen("employee-create")
    data object ClockInOut : Screen("clock-in-out")
    data object Notifications : Screen("notifications")
    data object Settings : Screen("settings")
    data object GlobalSearch : Screen("search")
    data object Scanner : Screen("scanner")
    data object More : Screen("more")

    // Leads
    data object Leads : Screen("leads")
    data object LeadDetail : Screen("leads/{id}") {
        fun createRoute(id: Long) = "leads/$id"
    }
    data object LeadCreate : Screen("lead-create")

    // Appointments (part of leads module)
    data object Appointments : Screen("appointments")
    data object AppointmentCreate : Screen("appointment-create")

    // Estimates
    data object Estimates : Screen("estimates")
    data object EstimateDetail : Screen("estimates/{id}") {
        fun createRoute(id: Long) = "estimates/$id"
    }

    // Expenses
    data object Expenses : Screen("expenses")
    data object ExpenseCreate : Screen("expense-create")

    // Inventory CRUD
    data object InventoryCreate : Screen("inventory-create")
    data object InventoryEdit : Screen("inventory-edit/{id}") {
        fun createRoute(id: Long) = "inventory-edit/$id"
    }

    // Settings children
    data object SmsTemplates : Screen("settings/sms-templates")
    data object Profile : Screen("settings/profile")

    // §2.6 — Security sub-screen (biometric unlock + Change PIN + Change Password + Lock now).
    data object Security : Screen("settings/security")

    // CROSS38b-notif: Settings > Notifications preferences sub-page. Distinct
    // from `Notifications` (the notifications inbox list) per CROSS54.
    data object NotificationSettings : Screen("settings/notifications")

    // AUD-20260414-M5: "Sync Issues" screen — lists dead-letter sync_queue
    // entries with a per-row Retry button that resurrects them back into
    // the pending queue via SyncManager.retryDeadLetter. Entry point is a
    // badged tile on the Settings screen when count > 0.
    data object SyncIssues : Screen("sync-issues")

    // §2.5 PIN — Settings > Security > Set up PIN / Change PIN.
    // PinSetup composable handles both first-time setup and change-current-PIN
    // mode based on PinPreferences.isPinSet at entry time.
    data object PinSetup : Screen("settings/security/pin-setup")

    // §14.2 Employee detail — read-only profile screen reachable by tapping
    // a row on the employee list. Per-employee server endpoints (Reset PIN,
    // Toggle active, Edit) land later as a follow-up.
    data object EmployeeDetail : Screen("employees/{id}") {
        fun createRoute(id: Long) = "employees/$id"
    }

    // §32.3 Crash reports — Settings → Diagnostics. Lists files written by
    // util/CrashReporter to filesDir/crash-reports/.
    data object CrashReports : Screen("settings/diagnostics/crash-reports")

    // §1.3 [plan:L185] — Diagnostics (Export DB snapshot). DEBUG builds only.
    data object Diagnostics : Screen("settings/diagnostics")

    // §28 / §32 About + diagnostics — copy-bundle for support tickets.
    data object About : Screen("settings/about")

    // §2.1 — Setup-status gate: probes GET /auth/setup-status before showing
    // the login form. Shown when a serverUrl is saved but no session exists.
    data object SetupStatusGate : Screen("auth/setup-gate")

    // §2.9 — Change-password screen (authenticated; reachable from Security sub-screen).
    data object ChangePassword : Screen("settings/security/change-password")

    // §2.5 — Switch User (shared device): PIN entry to switch active identity.
    // Entry point: Settings > "Switch user" row (and TODO: long-press avatar in top bar).
    data object SwitchUser : Screen("settings/switch-user")

    // §27 — Per-app language picker (ActionPlan §27).
    data object Language : Screen("settings/language")

    // §1.4/§19/§30 — Theme picker: system/light/dark + Material You dynamic color.
    data object Theme : Screen("settings/theme")

    // §2.8 — Password reset + backup-code recovery screens (pre-auth)
    data object ForgotPassword : Screen("auth/forgot-password")
    data object ResetPassword : Screen("auth/reset-password/{token}") {
        fun createRoute(token: String) = "auth/reset-password/$token"
    }
    data object BackupCodeRecovery : Screen("auth/backup-recovery")
}

data class BottomNavItem(
    val screen: Screen,
    val label: String,
    val icon: @Composable () -> Unit,
)

/**
 * Translate a raw route string resolved by MainActivity into the nav route
 * to actually navigate to. Two categories feed in here:
 *
 *   1. AND-20260414-H1 external deep links (launcher shortcut / App Actions
 *      / QS tile) advertise stable contract strings like `ticket/new` and
 *      `customer/new`. These differ from the internal nav destinations
 *      (`ticket-create`, `customer-create`) so we map them via the first
 *      branch.
 *   2. AND-20260414-H2 FCM notification taps resolve to internal routes
 *      directly (e.g. `tickets/123`, `invoices/45`), so they pass through
 *      the fallback branch unchanged.
 *
 * Returns null for routes that don't correspond to a known destination, in
 * which case the caller should leave the user on the start destination.
 */
private fun mapResolvedRoute(raw: String): String? = when (raw) {
    // External H1 contract routes → internal nav destinations
    "ticket/new"   -> Screen.TicketCreate.route
    "customer/new" -> Screen.CustomerCreate.route
    "scan"         -> Screen.Scanner.route
    // FCM H2 routes (tickets/{id}, invoices/{id}, etc.) are already
    // internal — forward them as-is. Static routes like `messages`,
    // `notifications`, `appointments`, `expenses` are also valid internal
    // destinations.
    else -> raw
}

@Composable
fun AppNavGraph(
    authPreferences: AuthPreferences? = null,
    serverReachabilityMonitor: ServerReachabilityMonitor? = null,
    syncQueueDao: SyncQueueDao? = null,
    syncManager: SyncManager? = null,
    deepLinkBus: DeepLinkBus? = null,
    breadcrumbs: com.bizarreelectronics.crm.util.Breadcrumbs? = null,
    clockDrift: ClockDrift? = null,
    rateLimiter: RateLimiter? = null,
    sessionTimeout: SessionTimeout? = null,
) {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    // §32.5 — log every nav route change so the breadcrumb tail in any
    // future crash log shows the user's path leading up to the throwable.
    LaunchedEffect(currentRoute) {
        currentRoute?.let { breadcrumbs?.log(com.bizarreelectronics.crm.util.Breadcrumbs.CAT_NAV, it) }
    }

    // Observe auth expiry: when AuthInterceptor fails to refresh and clears
    // prefs, navigate the user back to the login screen + pass the reason
    // so the login screen can render a "you've been signed out" banner
    // (§28.6 / §2.11). Pure UserLogout doesn't set the flag — no banner.
    LaunchedEffect(authPreferences) {
        authPreferences?.authCleared?.collect { reason ->
            navController.navigate(Screen.Login.route) {
                popUpTo(0) { inclusive = true }
            }
            if (reason != com.bizarreelectronics.crm.data.local.prefs.AuthPreferences.ClearReason.UserLogout) {
                navController.currentBackStackEntry
                    ?.savedStateHandle
                    ?.set("session_revoked_reason", reason.name)
            }
        }
    }

    // AND-20260414-H1 + AND-20260414-H2: consume whatever MainActivity
    // resolved from the launch / onNewIntent intent — either an external
    // deep-link path (`ticket/new`, `customer/new`, `scan`) or an FCM
    // notification tap translated into an internal detail route
    // (`tickets/{id}`, `invoices/{id}`, `customers/{id}`, …). We consume
    // the bus value immediately after dispatching the navigate call so
    // rotation / dark-mode-toggle doesn't re-fire the same route.
    //
    // Route is gated on login state: if the user hits a push before
    // authenticating, we keep the route queued until the login screen
    // finishes and the composition re-runs with a logged-in start
    // destination. Unknown routes (mapResolvedRoute returns null) are
    // dropped so a malformed push payload can't crash the navigate call.
    LaunchedEffect(deepLinkBus, authPreferences?.isLoggedIn) {
        deepLinkBus?.pendingRoute?.collect { raw ->
            if (raw == null) return@collect
            if (authPreferences?.isLoggedIn != true) return@collect
            val dest = mapResolvedRoute(raw)
            if (dest != null) {
                navController.navigate(dest)
            }
            // Always consume — even for unknown routes — so we don't spin
            // on a payload the app can't handle.
            deepLinkBus.consume()
        }
    }

    // Routes that are children of the "More" tab
    val moreChildRoutes = setOf(
        Screen.Customers.route, Screen.Inventory.route, Screen.Invoices.route,
        Screen.Reports.route, Screen.Employees.route, Screen.Notifications.route,
        Screen.Settings.route, Screen.GlobalSearch.route,
        Screen.Leads.route, Screen.Estimates.route, Screen.Expenses.route,
        Screen.Appointments.route,
    )

    // Determine if we should show the bottom nav.
    //
    // @audit-fixed: previously the inventory check was only !startsWith("inventory/")
    // which did NOT match Screen.InventoryEdit.route ("inventory-edit/{id}")
    // because the prefix uses a dash, not a slash. The bottom nav was visible
    // on the inventory edit screen even though every other detail/edit screen
    // hides it. Adding an explicit startsWith("inventory-edit/") closes the
    // gap without affecting the InventoryCreate single-route check below.
    //
    // TODO(nav-refactor): This 18-clause string-prefix chain is brittle — every new
    //  detail or create route risks a bar-flash if the implementer forgets to add a
    //  clause here. Proposed fix: add a `hidesBottomBar: Boolean` property to the
    //  sealed `Screen` class so the ruleset is co-located with the route definition.
    //  Example:
    //
    //    sealed class Screen(val route: String, val hidesBottomBar: Boolean = false) {
    //        data object Login        : Screen("login",         hidesBottomBar = true)
    //        data object TicketDetail : Screen("tickets/{id}",  hidesBottomBar = true) { … }
    //        // etc.
    //    }
    //
    //  Then: val showBottomNav = Screen.all.firstOrNull { it.route == currentRoute }
    //            ?.hidesBottomBar?.not() ?: false
    //
    //  Risk: route-matching by sealed-class property works for exact routes but
    //  requires a startsWith()-style matcher for parameterised routes
    //  (e.g. "tickets/42"). A helper like `fun Screen.matches(route: String)` would
    //  be needed, making this a small but intentional routing refactor — evaluate
    //  when next adding detail routes rather than as a standalone change.
    val showBottomNav = currentRoute != null &&
            currentRoute != Screen.Login.route &&
            !currentRoute.startsWith("tickets/") &&
            // CROSS47-seed: the registered route is now
            // `ticket-create?customerId={customerId}`, so an exact equality
            // check against the bare `ticket-create` literal would never hit
            // and the wizard would wrongly show the bottom-nav. Match by
            // prefix instead.
            !currentRoute.startsWith(Screen.TicketCreate.route) &&
            currentRoute != Screen.ClockInOut.route &&
            currentRoute != Screen.EmployeeCreate.route &&
            !currentRoute.startsWith("customers/") &&
            currentRoute != Screen.CustomerCreate.route &&
            !currentRoute.startsWith("invoices/") &&
            currentRoute != Screen.InvoiceCreate.route &&
            !currentRoute.startsWith("inventory/") &&
            !currentRoute.startsWith("inventory-edit/") &&
            currentRoute != Screen.InventoryCreate.route &&
            !currentRoute.startsWith("messages/") &&
            !currentRoute.startsWith("checkout/") &&
            !currentRoute.startsWith("ticket-success/") &&
            !currentRoute.startsWith("leads/") &&
            currentRoute != Screen.LeadCreate.route &&
            currentRoute != Screen.AppointmentCreate.route &&
            !currentRoute.startsWith("estimates/") &&
            currentRoute != Screen.ExpenseCreate.route &&
            !currentRoute.startsWith("settings/") &&
            currentRoute != Screen.Scanner.route &&
            // AUD-20260414-M5: Sync Issues is a modal-ish diagnostic screen
            // reached from Settings, so hide the bottom bar like other
            // non-root detail routes.
            currentRoute != Screen.SyncIssues.route &&
            // §2.8 — pre-auth password-reset screens hide the bottom bar
            currentRoute != Screen.ForgotPassword.route &&
            !currentRoute.startsWith("auth/reset-password/") &&
            currentRoute != Screen.BackupCodeRecovery.route &&
            // §2.1 — setup-status gate is a pre-auth transient screen
            currentRoute != Screen.SetupStatusGate.route

    val bottomNavItems = listOf(
        BottomNavItem(Screen.Dashboard, "Dashboard") { Icon(Icons.Default.Home, "Dashboard") },
        BottomNavItem(Screen.Tickets, "Tickets") { Icon(Icons.Default.ConfirmationNumber, "Tickets") },
        BottomNavItem(Screen.Pos, "POS") { Icon(Icons.Default.PointOfSale, "POS") },
        BottomNavItem(Screen.Messages, "Messages") { Icon(Icons.Default.Chat, "Messages") },
        BottomNavItem(Screen.More, "More") { Icon(Icons.Default.MoreHoriz, "More") },
    )

    Scaffold(
        // CROSS18: zero the outer Scaffold's top inset so child screens' own
        // TopAppBar is the sole owner of statusBars padding. Without this,
        // `padding` below carries the status bar height, the inner NavHost's
        // child Scaffolds re-apply it via their BrandTopAppBar, and the two
        // stack to ~200px of dead space above the title on every wizard /
        // list screen (Dashboard / Customers / Messages / TicketCreate).
        // Horizontal + Bottom stay on so the bottom navigation bar still
        // pushes content up and side insets (gesture nav / cutouts) are
        // honored.
        contentWindowInsets = WindowInsets.systemBars.only(
            WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom,
        ),
        bottomBar = {
            // §22.2 — drop the bottom NavigationBar at tablet+ widths; the
            // NavigationRail rendered alongside the NavHost (below) takes
            // over for ≥600dp. Phone width keeps the bottom bar so muscle
            // memory + thumb-reach stays right.
            val tabletNav = com.bizarreelectronics.crm.util.isMediumOrExpandedWidth()
            if (showBottomNav && !tabletNav) {
                // [P0] NavigationBar restyle: explicit surface container so the bar
                // stays anchored to surface1 and does not shift on scroll (Material3
                // default is surfaceContainer which responds to scroll elevation).
                // Selected indicator pill and icon tint come from the theme (purple
                // primary via Wave 1 palette). Labels stay sentence-case in labelSmall
                // Inter body-sans — do NOT convert to ALL-CAPS.
                NavigationBar(
                    containerColor = MaterialTheme.colorScheme.surface,
                ) {
                    bottomNavItems.forEach { item ->
                        val isMoreTab = item.screen == Screen.More
                        val isSelected = if (isMoreTab) {
                            currentRoute == Screen.More.route || currentRoute in moreChildRoutes
                        } else {
                            currentRoute == item.screen.route
                        }
                        NavigationBarItem(
                            selected = isSelected,
                            onClick = {
                                if (isMoreTab) {
                                    // Always navigate to the More menu, never restore a child
                                    navController.navigate(Screen.More.route) {
                                        popUpTo(navController.graph.findStartDestination().id) {
                                            saveState = false
                                        }
                                        launchSingleTop = true
                                        restoreState = false
                                    }
                                } else {
                                    navController.navigate(item.screen.route) {
                                        popUpTo(navController.graph.findStartDestination().id) {
                                            saveState = true
                                        }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                }
                            },
                            icon = item.icon,
                            label = { Text(item.label, style = MaterialTheme.typography.labelSmall) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        val canShowOfflineBanner = authPreferences?.isLoggedIn == true &&
            !authPreferences.serverUrl.isNullOrBlank() &&
            currentRoute != null &&
            currentRoute != Screen.Login.route

        val isOffline = if (canShowOfflineBanner) serverReachabilityMonitor?.let {
            val effectivelyOnline by it.isEffectivelyOnline.collectAsState()
            !effectivelyOnline
        } ?: false else false

        val pendingSyncCount = syncQueueDao?.let {
            val count by it.getCount().collectAsState(initial = 0)
            count
        } ?: 0

        val isSyncing = syncManager?.let {
            val syncing by it.isSyncing.collectAsState()
            syncing
        } ?: false

        Column(modifier = Modifier.padding(padding)) {
            OfflineBanner(
                isOffline = isOffline,
                pendingSyncCount = pendingSyncCount,
                isSyncing = isSyncing,
            )

            // §1 L251 — clock-drift warning; only meaningful when logged in.
            if (authPreferences?.isLoggedIn == true && clockDrift != null) {
                ClockDriftBanner(clockDrift = clockDrift)
            }

            // §1 L257 — rate-limit slow-down banner; only meaningful when logged in.
            if (authPreferences?.isLoggedIn == true && rateLimiter != null) {
                RateLimitBanner(rateLimiter = rateLimiter)
            }

            // §17.10 — global hardware-keyboard shortcuts. Wraps the NavHost
            // so the same key chord works on every screen. Only fires when a
            // physical keyboard is attached + the focusable Box claims focus
            // (no-op on phones).
            com.bizarreelectronics.crm.util.KeyboardShortcutsHost(
                onNewTicket = { navController.navigate(Screen.TicketCreate.route) },
                onNewCustomer = { navController.navigate(Screen.CustomerCreate.route) },
                onScanBarcode = { navController.navigate(Screen.Scanner.route) },
                onNewSms = { navController.navigate(Screen.Messages.route) },
                onGlobalSearch = { navController.navigate(Screen.GlobalSearch.route) },
                onSettings = { navController.navigate(Screen.Settings.route) },
                onHome = {
                    // Pop to the dashboard root without stacking it again.
                    navController.navigate(Screen.Dashboard.route) {
                        popUpTo(Screen.Dashboard.route) { inclusive = false }
                        launchSingleTop = true
                    }
                },
                onBack = {
                    if (!navController.popBackStack()) {
                        // Already on the root — fall back to Dashboard.
                        navController.navigate(Screen.Dashboard.route) {
                            popUpTo(Screen.Dashboard.route) { inclusive = false }
                            launchSingleTop = true
                        }
                    }
                },
            ) {
            // §22.2 — at tablet+ widths render NavigationRail alongside the
            // NavHost in a Row. Phones fall through to single-column.
            val tabletNav = com.bizarreelectronics.crm.util.isMediumOrExpandedWidth()
            androidx.compose.foundation.layout.Row(
                modifier = Modifier.weight(1f).fillMaxSize(),
            ) {
                if (tabletNav && showBottomNav) {
                    NavigationRail(
                        containerColor = MaterialTheme.colorScheme.surface,
                    ) {
                        bottomNavItems.forEach { item ->
                            val isMoreTab = item.screen == Screen.More
                            val isSelected = if (isMoreTab) {
                                currentRoute == Screen.More.route || currentRoute in moreChildRoutes
                            } else {
                                currentRoute == item.screen.route
                            }
                            androidx.compose.material3.NavigationRailItem(
                                selected = isSelected,
                                onClick = {
                                    if (isMoreTab) {
                                        navController.navigate(Screen.More.route) {
                                            popUpTo(navController.graph.findStartDestination().id) {
                                                saveState = false
                                            }
                                            launchSingleTop = true
                                            restoreState = false
                                        }
                                    } else {
                                        navController.navigate(item.screen.route) {
                                            popUpTo(navController.graph.findStartDestination().id) {
                                                saveState = true
                                            }
                                            launchSingleTop = true
                                            restoreState = true
                                        }
                                    }
                                },
                                icon = item.icon,
                                label = { Text(item.label, style = MaterialTheme.typography.labelSmall) },
                            )
                        }
                    }
                    androidx.compose.material3.VerticalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                    )
                }
            // §2.1 — start-destination logic:
            //   isLoggedIn + serverUrl   → Dashboard (already authenticated)
            //   !isLoggedIn + serverUrl  → SetupStatusGate (probe then login)
            //   no serverUrl             → Login (user enters server URL first)
            val hasServerUrl = !authPreferences?.serverUrl.isNullOrBlank()
            val startDest = when {
                authPreferences?.isLoggedIn == true && hasServerUrl -> Screen.Dashboard.route
                hasServerUrl && authPreferences?.isLoggedIn != true -> Screen.SetupStatusGate.route
                else -> Screen.Login.route
            }
            NavHost(
                navController = navController,
                startDestination = startDest,
                modifier = Modifier.weight(1f),
                enterTransition = { fadeIn(animationSpec = tween(200)) },
                exitTransition = { fadeOut(animationSpec = tween(200)) },
                popEnterTransition = { fadeIn(animationSpec = tween(200)) },
                popExitTransition = { fadeOut(animationSpec = tween(200)) },
            ) {
            composable(Screen.Login.route) { entry ->
                // §28.6 — pick up the reason set by the authCleared observer
                // so the LoginScreen can show "you've been signed out" copy.
                val sessionRevokedReason by entry.savedStateHandle
                    .getStateFlow<String?>("session_revoked_reason", null)
                    .collectAsState()
                LoginScreen(
                    onLoginSuccess = {
                        navController.navigate(Screen.Dashboard.route) {
                            popUpTo(Screen.Login.route) { inclusive = true }
                        }
                    },
                    sessionRevokedReason = sessionRevokedReason,
                    onSessionBannerDismissed = {
                        entry.savedStateHandle["session_revoked_reason"] = null
                    },
                    // §2.8 — show on credentials step; routes to forgot-password flow
                    onForgotPassword = {
                        navController.navigate(Screen.ForgotPassword.route)
                    },
                    // §2.8 L335 — shown on the 2FA verify step; routes to backup-code recovery
                    onBackupCodeRecovery = {
                        navController.navigate(Screen.BackupCodeRecovery.route)
                    },
                )
            }
            // §2.1 — Setup-status gate: probes the server before rendering login.
            // Routing decisions:
            //   needsSetup=true    → Login (shows "contact admin" banner; §2.10 flow TBD)
            //   isMultiTenant=true → Login (tenant picker TBD in §2.10)
            //   normal             → Login (credentials step)
            // The gate always resolves to the Login screen in this release since the
            // InitialSetupFlow (§2.10) and TenantPicker don't exist yet.  The login
            // screen's own probe (CredentialsStep LaunchedEffect) then re-shows the
            // needs-setup banner if appropriate.
            composable(Screen.SetupStatusGate.route) {
                SetupStatusGateScreen(
                    onNeedsSetup = {
                        // §2.10 not yet implemented — fall through to login which
                        // will display the "contact admin" banner via its own probe.
                        navController.navigate(Screen.Login.route) {
                            popUpTo(Screen.SetupStatusGate.route) { inclusive = true }
                        }
                    },
                    onMultiTenant = {
                        // TODO(§2.10): tenant picker doesn't exist yet — go to login.
                        navController.navigate(Screen.Login.route) {
                            popUpTo(Screen.SetupStatusGate.route) { inclusive = true }
                        }
                    },
                    onLogin = {
                        navController.navigate(Screen.Login.route) {
                            popUpTo(Screen.SetupStatusGate.route) { inclusive = true }
                        }
                    },
                )
            }
            // §2.8 — Forgot password: user enters their email to receive a reset link.
            composable(Screen.ForgotPassword.route) {
                ForgotPasswordScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            // §2.8 — Reset password: token arrives via nav arg (App Link or manual entry).
            // On 410/expired the screen shows a CTA that routes back to ForgotPasswordScreen.
            // Deep links cover both the HTTPS App Link and the custom-scheme variant so the
            // reset email works regardless of OS App Link verification status.
            composable(
                route = Screen.ResetPassword.route,
                arguments = listOf(
                    navArgument("token") { type = NavType.StringType },
                ),
                deepLinks = listOf(
                    navDeepLink { uriPattern = "https://app.bizarrecrm.com/reset-password/{token}" },
                    navDeepLink { uriPattern = "bizarrecrm://reset-password/{token}" },
                ),
            ) {
                ResetPasswordScreen(
                    onBack = { navController.popBackStack() },
                    onSuccess = {
                        navController.navigate(Screen.Login.route) {
                            popUpTo(0) { inclusive = true }
                        }
                    },
                    onExpired = {
                        navController.navigate(Screen.ForgotPassword.route) {
                            popUpTo(Screen.ForgotPassword.route) { inclusive = true }
                        }
                    },
                )
            }
            // §2.8 — Backup-code recovery: email + backup code + new password.
            // On success navigate back to Login so the user can sign in fresh.
            composable(Screen.BackupCodeRecovery.route) {
                BackupCodeRecoveryScreen(
                    onBack = { navController.popBackStack() },
                    onSuccess = {
                        navController.navigate(Screen.Login.route) {
                            popUpTo(0) { inclusive = true }
                        }
                    },
                )
            }
            composable(Screen.Dashboard.route) {
                DashboardScreen(
                    onNavigateToTicket = { id -> navController.navigate(Screen.TicketDetail.createRoute(id)) },
                    onNavigateToTickets = { navController.navigate(Screen.Tickets.route) },
                    onCreateTicket = { navController.navigate(Screen.TicketCreate.route) },
                    onCreateCustomer = { navController.navigate(Screen.CustomerCreate.route) },
                    onLogSale = { navController.navigate(Screen.Pos.route) },
                    onScanBarcode = { navController.navigate(Screen.Scanner.route) },
                    onNavigateToNotifications = { navController.navigate(Screen.Notifications.route) },
                    onClockInOut = { navController.navigate(Screen.ClockInOut.route) },
                    // §3.1 — KPI tile taps deep-link to the filtered list.
                    onNavigateToAppointments = { navController.navigate(Screen.Appointments.route) },
                    onNavigateToInventory = { navController.navigate(Screen.Inventory.route) },
                    // §3.9 — tap greeting → Settings → Profile so the user
                    // has a one-tap path to edit their name / avatar from the
                    // dashboard without drilling through Settings.
                    onNavigateToProfile = { navController.navigate(Screen.Profile.route) },
                    // §3.10 — when pending rows are stuck, the badge tap
                    // routes to Sync Issues instead of force-syncing again.
                    onNavigateToSyncIssues = { navController.navigate(Screen.SyncIssues.route) },
                )
            }
            composable(Screen.Tickets.route) {
                TicketListScreen(
                    onTicketClick = { id -> navController.navigate(Screen.TicketDetail.createRoute(id)) },
                    onCreateClick = { navController.navigate(Screen.TicketCreate.route) },
                )
            }
            composable(Screen.TicketDetail.route) { backStackEntry ->
                val ticketId = backStackEntry.arguments?.getString("id")?.toLongOrNull() ?: return@composable
                TicketDetailScreen(
                    ticketId = ticketId,
                    onBack = { navController.popBackStack() },
                    onNavigateToCustomer = { id -> navController.navigate(Screen.CustomerDetail.createRoute(id)) },
                    onNavigateToSms = { phone -> navController.navigate(Screen.SmsThread.createRoute(phone)) },
                    // AND-20260414-H3: after a successful Convert-to-Invoice, land
                    // the user on the new invoice so they can review or collect
                    // payment, rather than leaving them stranded on the ticket.
                    onNavigateToInvoice = { id -> navController.navigate(Screen.InvoiceDetail.createRoute(id)) },
                    onEditDevice = { deviceId ->
                        navController.navigate(Screen.TicketDeviceEdit.createRoute(ticketId, deviceId))
                    },
                    // AND-20260414-M1: navigate to the photo gallery / capture
                    // screen bound to this ticket + device id. bug:gallery-400 fix:
                    // the server's POST /:id/photos route requires ticket_device_id
                    // in the body, so we thread deviceId through the route.
                    onAddPhotos = { id, deviceId ->
                        navController.navigate(Screen.TicketPhotos.createRoute(id, deviceId))
                    },
                    // AND-20260414-H4: wire the payment screen so the top-bar
                    // Checkout action can reach it. The detail screen pulls
                    // the total + customer display name from its DTO so the
                    // summary card and payment-method gates are populated
                    // without a second API round-trip.
                    onCheckout = { id, total, customerName ->
                        navController.navigate(
                            Screen.Checkout.createRoute(
                                ticketId = id,
                                total = total,
                                customerName = customerName,
                            )
                        )
                    },
                )
            }
            composable(Screen.TicketDeviceEdit.route) { backStackEntry ->
                val ticketId = backStackEntry.arguments?.getString("ticketId")?.toLongOrNull() ?: return@composable
                val deviceId = backStackEntry.arguments?.getString("deviceId")?.toLongOrNull() ?: return@composable
                TicketDeviceEditScreen(
                    ticketId = ticketId,
                    deviceId = deviceId,
                    onBack = { navController.popBackStack() },
                )
            }
            // AND-20260414-M1: photo upload / gallery picker for a ticket.
            // Reads `ticketId` and `deviceId` from the route path; the VM owns
            // the upload state, so we only need to pass the ids + a back callback.
            // bug:gallery-400 fix: deviceId is now part of the route so the VM
            // can include it in the multipart body as ticket_device_id.
            composable(Screen.TicketPhotos.route) { backStackEntry ->
                val ticketId = backStackEntry.arguments?.getString("ticketId")?.toLongOrNull() ?: return@composable
                val deviceId = backStackEntry.arguments?.getString("deviceId")?.toLongOrNull() ?: return@composable
                PhotoCaptureScreen(
                    ticketId = ticketId,
                    deviceId = deviceId,
                    onBack = { navController.popBackStack() },
                )
            }
            composable(
                // CROSS47-seed: optional `customerId` query arg. The VM reads
                // it from SavedStateHandle and pre-selects the customer so the
                // wizard opens on the Category step when launched from a
                // customer detail screen.
                route = Screen.TicketCreate.route + "?customerId={customerId}",
                arguments = listOf(
                    navArgument("customerId") {
                        type = NavType.StringType
                        nullable = true
                        defaultValue = null
                    },
                ),
            ) {
                com.bizarreelectronics.crm.ui.screens.tickets.TicketCreateScreen(
                    onBack = { navController.popBackStack() },
                    onCreated = { id ->
                        navController.navigate(Screen.TicketSuccess.createRoute(id)) {
                            popUpTo(Screen.Tickets.route)
                        }
                    },
                )
            }
            composable(Screen.Customers.route) {
                CustomerListScreen(
                    onCustomerClick = { id -> navController.navigate(Screen.CustomerDetail.createRoute(id)) },
                    onCreateClick = { navController.navigate(Screen.CustomerCreate.route) },
                )
            }
            composable(Screen.CustomerDetail.route) { backStackEntry ->
                val customerId = backStackEntry.arguments?.getString("id")?.toLongOrNull() ?: return@composable
                CustomerDetailScreen(
                    customerId = customerId,
                    onBack = { navController.popBackStack() },
                    onNavigateToTicket = { id -> navController.navigate(Screen.TicketDetail.createRoute(id)) },
                    onNavigateToSms = { phone -> navController.navigate(Screen.SmsThread.createRoute(phone)) },
                    // CROSS47 + CROSS47-seed: pass the customer id so the
                    // wizard pre-selects the customer and opens on the
                    // Category step instead of forcing a second customer
                    // picker trip.
                    onCreateTicket = { id -> navController.navigate(Screen.TicketCreate.createRoute(id)) },
                )
            }
            composable(Screen.CustomerCreate.route) {
                com.bizarreelectronics.crm.ui.screens.customers.CustomerCreateScreen(
                    onBack = { navController.popBackStack() },
                    onCreated = { id ->
                        navController.navigate(Screen.CustomerDetail.createRoute(id)) {
                            popUpTo(Screen.Customers.route)
                        }
                    },
                )
            }
            composable(Screen.Pos.route) {
                PosScreen(
                    onNavigateToTicketCreate = { navController.navigate(Screen.TicketCreate.route) },
                    onNavigateToTicket = { id -> navController.navigate(Screen.TicketDetail.createRoute(id)) },
                )
            }
            // AND-20260414-H4: declare typed nav arguments so `ticketId` arrives
            // as a Long, `total` as a Float (NavType has no DoubleType — see
            // androidx.navigation.NavType), and `customerName` as a nullable
            // String. Previously the route had no `navArgument(...)` declarations
            // so every path segment was coerced into a String, and the
            // CheckoutViewModel's `savedStateHandle.get<Long>("ticketId")` call
            // silently returned null, booting the screen with ticket 0, a blank
            // customer, and a $0.00 total. `Screen.Checkout.createRoute()` had
            // no call sites either, so the screen was effectively dead code.
            composable(
                route = Screen.Checkout.route,
                arguments = listOf(
                    navArgument("ticketId") { type = NavType.LongType },
                    // AUDIT-AND-004: use StringType instead of FloatType to
                    // avoid the Double→Float→Double precision loss. $99.99
                    // serialised through FloatType round-trips as 99.9899...
                    // because IEEE-754 single-precision cannot represent all
                    // decimal currency values exactly. createRoute() already
                    // formats the value to "%.2f" so the URL segment is always
                    // a fixed-point decimal string; we parse it back via
                    // toBigDecimal() which preserves the exact representation.
                    navArgument("total") {
                        type = NavType.StringType
                        nullable = true
                        defaultValue = "0.00"
                    },
                    navArgument("customerName") {
                        type = NavType.StringType
                        nullable = true
                    },
                ),
            ) { backStackEntry ->
                val ticketId = backStackEntry.arguments?.getLong("ticketId") ?: 0L
                // AUDIT-AND-004: parse the fixed-point string via toBigDecimal()
                // to recover the exact decimal value that createRoute() formatted.
                val total = backStackEntry.arguments?.getString("total")
                    ?.toBigDecimalOrNull()
                    ?.toDouble()
                    ?: 0.0
                val rawName = backStackEntry.arguments?.getString("customerName")
                val customerName = rawName?.let { Uri.decode(it) } ?: ""
                CheckoutScreen(
                    ticketId = ticketId,
                    total = total,
                    customerName = customerName,
                    onBack = { navController.popBackStack() },
                    onSuccess = { id ->
                        navController.navigate(Screen.TicketSuccess.createRoute(id)) {
                            popUpTo(Screen.Tickets.route)
                        }
                    },
                )
            }
            composable(
                route = Screen.TicketSuccess.route + "?orderId={orderId}",
                arguments = listOf(
                    navArgument("orderId") {
                        type = NavType.StringType
                        nullable = true
                        defaultValue = null
                    },
                ),
            ) { backStackEntry ->
                val ticketId = backStackEntry.arguments?.getString("ticketId")?.toLongOrNull() ?: return@composable
                val orderId = backStackEntry.arguments?.getString("orderId")
                TicketSuccessScreen(
                    ticketId = ticketId,
                    ticketOrderId = orderId,
                    onViewTicket = { id ->
                        navController.navigate(Screen.TicketDetail.createRoute(id)) {
                            popUpTo(Screen.Dashboard.route)
                        }
                    },
                    onNewTicket = {
                        navController.navigate(Screen.TicketCreate.route) {
                            popUpTo(Screen.Dashboard.route)
                        }
                    },
                )
            }
            composable(Screen.Inventory.route) { backStackEntry ->
                val scannedBarcode by backStackEntry.savedStateHandle
                    .getStateFlow<String?>("scanned_barcode", null)
                    .collectAsState()

                InventoryListScreen(
                    onItemClick = { id -> navController.navigate(Screen.InventoryDetail.createRoute(id)) },
                    onScanClick = { navController.navigate(Screen.Scanner.route) },
                    onAddClick = { navController.navigate(Screen.InventoryCreate.route) },
                    scannedBarcode = scannedBarcode,
                    onBarcodeLookupResult = { id ->
                        backStackEntry.savedStateHandle.remove<String>("scanned_barcode")
                        navController.navigate(Screen.InventoryDetail.createRoute(id))
                    },
                    onBarcodeLookupConsumed = {
                        backStackEntry.savedStateHandle.remove<String>("scanned_barcode")
                    },
                )
            }
            composable(Screen.Invoices.route) {
                InvoiceListScreen(
                    onInvoiceClick = { id -> navController.navigate(Screen.InvoiceDetail.createRoute(id)) },
                    onCreateClick = { navController.navigate(Screen.InvoiceCreate.route) },
                )
            }
            composable(Screen.InvoiceDetail.route) { backStackEntry ->
                val invoiceId = backStackEntry.arguments?.getString("id")?.toLongOrNull() ?: return@composable
                InvoiceDetailScreen(
                    invoiceId = invoiceId,
                    onBack = { navController.popBackStack() },
                    onNavigateToTicket = { id -> navController.navigate(Screen.TicketDetail.createRoute(id)) },
                )
            }
            composable(Screen.InvoiceCreate.route) {
                InvoiceCreateScreen(
                    onBack = { navController.popBackStack() },
                    onCreated = { id ->
                        navController.navigate(Screen.InvoiceDetail.createRoute(id)) {
                            popUpTo(Screen.Invoices.route)
                        }
                    },
                )
            }
            composable(Screen.InventoryDetail.route) { backStackEntry ->
                val itemId = backStackEntry.arguments?.getString("id")?.toLongOrNull() ?: return@composable
                InventoryDetailScreen(
                    itemId = itemId,
                    onBack = { navController.popBackStack() },
                    onEditItem = { id ->
                        navController.navigate(Screen.InventoryEdit.createRoute(id))
                    },
                )
            }
            composable(Screen.Messages.route) {
                SmsListScreen(
                    onConversationClick = { phone -> navController.navigate(Screen.SmsThread.createRoute(phone)) },
                )
            }
            composable(Screen.SmsThread.route) { backStackEntry ->
                val phone = backStackEntry.arguments?.getString("phone") ?: return@composable
                // AND-20260414-M4: expose the `sms_template_body` savedStateHandle key
                // as a StateFlow so SmsThreadScreen can observe a template picked in
                // SmsTemplatesScreen. The screen clears the key via onTemplateConsumed
                // once it has copied the body into the compose draft.
                val templateBodyFlow = backStackEntry.savedStateHandle
                    .getStateFlow<String?>("sms_template_body", null)
                SmsThreadScreen(
                    phone = phone,
                    onBack = { navController.popBackStack() },
                    onNavigateToTemplates = { navController.navigate(Screen.SmsTemplates.route) },
                    templateBodyFlow = templateBodyFlow,
                    onTemplateConsumed = {
                        backStackEntry.savedStateHandle.remove<String>("sms_template_body")
                    },
                )
            }
            composable(Screen.Notifications.route) {
                NotificationListScreen(
                    // AND-20260414-H2: widen in-app notification routing to
                    // match the entity types FcmService accepts on the push
                    // payload. Previously only ticket + invoice were routed
                    // in-app, so a notification row for a customer, lead,
                    // estimate, inventory item, or an SMS reply was a no-op
                    // tap. The mapping intentionally mirrors the whitelist
                    // in FcmService.ALLOWED_ENTITY_TYPES and the resolver in
                    // MainActivity.resolveFcmRoute so an FCM tap and an
                    // in-app row tap land on the same destination.
                    onNotificationClick = { type, id ->
                        when (type) {
                            "ticket"    -> id?.let { navController.navigate(Screen.TicketDetail.createRoute(it)) }
                            "invoice"   -> id?.let { navController.navigate(Screen.InvoiceDetail.createRoute(it)) }
                            "customer"  -> id?.let { navController.navigate(Screen.CustomerDetail.createRoute(it)) }
                            "lead"      -> id?.let { navController.navigate(Screen.LeadDetail.createRoute(it)) }
                            "estimate"  -> id?.let { navController.navigate(Screen.EstimateDetail.createRoute(it)) }
                            "inventory" -> id?.let { navController.navigate(Screen.InventoryDetail.createRoute(it)) }
                            // Types without a detail screen yet → land on
                            // the list so the user can locate the record.
                            "appointment" -> navController.navigate(Screen.Appointments.route)
                            "expense"     -> navController.navigate(Screen.Expenses.route)
                            // SMS entity_id is a message id, not a phone
                            // number — the thread route keys by phone, so
                            // we land on the inbox.
                            "sms"         -> navController.navigate(Screen.Messages.route)
                            else          -> Unit // drop unknown types silently
                        }
                    },
                    // CROSS55: top-bar settings gear → notification preferences
                    // (Settings > Notifications sub-page). Keeps the inbox and
                    // preferences separated per CROSS54 while making prefs
                    // reachable in one tap from the inbox.
                    onNavigateToPrefs = {
                        navController.navigate(Screen.NotificationSettings.route)
                    },
                )
            }
            composable(Screen.Reports.route) {
                ReportsScreen()
            }
            composable(Screen.Employees.route) { backStackEntry ->
                // When the create screen pops back it sets this flag — observe
                // it so we can trigger a refresh without a manual pull-to-refresh.
                val employeeCreated by backStackEntry.savedStateHandle
                    .getStateFlow("employee_created", false)
                    .collectAsState()

                EmployeeListScreen(
                    onClockInOutClick = { navController.navigate(Screen.ClockInOut.route) },
                    onCreateClick = { navController.navigate(Screen.EmployeeCreate.route) },
                    onEmployeeClick = { id ->
                        navController.navigate(Screen.EmployeeDetail.createRoute(id))
                    },
                    refreshTrigger = employeeCreated,
                    onRefreshConsumed = {
                        backStackEntry.savedStateHandle["employee_created"] = false
                    },
                )
            }
            composable(
                route = Screen.EmployeeDetail.route,
                arguments = listOf(navArgument("id") { type = NavType.LongType }),
            ) {
                com.bizarreelectronics.crm.ui.screens.employees.EmployeeDetailScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.EmployeeCreate.route) {
                // On successful creation write a signal to the previous back
                // stack entry so EmployeeListScreen reloads the list — that VM
                // instance is preserved across navigation and otherwise keeps
                // showing a stale snapshot.
                com.bizarreelectronics.crm.ui.screens.employees.EmployeeCreateScreen(
                    onBack = { navController.popBackStack() },
                    onCreated = {
                        navController.previousBackStackEntry
                            ?.savedStateHandle
                            ?.set("employee_created", true)
                        navController.popBackStack()
                    },
                )
            }
            composable(Screen.ClockInOut.route) {
                ClockInOutScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.Settings.route) {
                SettingsScreen(
                    onLogout = {
                        navController.navigate(Screen.Login.route) {
                            popUpTo(0) { inclusive = true }
                        }
                    },
                    onEditProfile = { navController.navigate(Screen.Profile.route) },
                    onNotificationSettings = { navController.navigate(Screen.NotificationSettings.route) },
                    // §27 — Language picker sub-screen.
                    onLanguage = { navController.navigate(Screen.Language.route) },
                    // §1.4/§19/§30 — Theme picker sub-screen.
                    onTheme = { navController.navigate(Screen.Theme.route) },
                    // §2.6 — Security sub-screen (biometric + PIN + password + lock now).
                    onSecurity = { navController.navigate(Screen.Security.route) },
                    // AUD-20260414-M5: entry into the Sync Issues diagnostic
                    // screen. The SettingsScreen gates the tile on
                    // count > 0 so this callback only fires when there is
                    // actually something for the user to triage.
                    onSyncIssues = { navController.navigate(Screen.SyncIssues.route) },
                    onPinSetup = { navController.navigate(Screen.PinSetup.route) },
                    onCrashReports = { navController.navigate(Screen.CrashReports.route) },
                    onAbout = { navController.navigate(Screen.About.route) },
                    // §2.5 — Switch user (shared device): navigate to PIN entry.
                    onSwitchUser = { navController.navigate(Screen.SwitchUser.route) },
                    // §1.3 [plan:L185] — Diagnostics → Export DB snapshot. DEBUG only.
                    onDiagnostics = { navController.navigate(Screen.Diagnostics.route) },
                )
            }
            composable(Screen.CrashReports.route) {
                com.bizarreelectronics.crm.ui.screens.settings.CrashReportsScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            // §1.3 [plan:L185] — Diagnostics (Export DB snapshot). DEBUG builds only;
            // SettingsScreen never navigates here in release builds.
            composable(Screen.Diagnostics.route) {
                DiagnosticsScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.About.route) {
                com.bizarreelectronics.crm.ui.screens.settings.AboutScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.PinSetup.route) {
                com.bizarreelectronics.crm.ui.auth.PinSetupScreen(
                    onDone = { navController.popBackStack() },
                    onCancel = { navController.popBackStack() },
                )
            }
            composable(Screen.Profile.route) {
                ProfileScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.NotificationSettings.route) {
                NotificationSettingsScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            // §2.6 — Security sub-screen: biometric unlock toggle + Change PIN
            // + Change Password + Lock Now.
            // PinPreferences is injected into SecurityViewModel via Hilt.
            composable(Screen.Security.route) {
                SecurityScreen(
                    onBack = { navController.popBackStack() },
                    onChangePin = { navController.navigate(Screen.PinSetup.route) },
                    // §2.9: Change-password screen wired (ActionPlan L340).
                    onChangePassword = { navController.navigate(Screen.ChangePassword.route) },
                )
            }
            // §2.9 — Change-password screen (authenticated, under Security).
            composable(Screen.ChangePassword.route) {
                ChangePasswordScreen(
                    onBack = { navController.popBackStack() },
                    onPasswordChanged = { navController.popBackStack() },
                )
            }
            // §2.5 — Switch User (shared device): PIN entry, reachable from
            // Settings > "Switch user" row. On success the new identity is
            // persisted and the user is sent to Dashboard with the back-stack
            // cleared to Dashboard (no stale Settings entry for old identity).
            composable(Screen.SwitchUser.route) {
                SwitchUserScreen(
                    onBack = { navController.popBackStack() },
                    onSwitched = {
                        navController.navigate(Screen.Dashboard.route) {
                            popUpTo(Screen.Dashboard.route) { inclusive = true }
                        }
                    },
                )
            }
            // §27 — Language picker: per-app language selection.
            // On API 33+ the OS recreates the activity after setApplicationLocales;
            // on older APIs LanguageScreen triggers recreate() explicitly.
            composable(Screen.Language.route) {
                LanguageScreen(
                    onBack = { navController.popBackStack() },
                )
            }

            // §1.4/§19/§30 — Theme picker: system/light/dark + Material You.
            // Changes are applied immediately via AppPreferences StateFlows;
            // no activity recreate is needed.
            composable(Screen.Theme.route) {
                ThemeScreen(
                    onBack = { navController.popBackStack() },
                )
            }

            // AUD-20260414-M5: Sync Issues screen — lists dead-letter
            // sync_queue entries with per-row Retry. Entry point is a badged
            // tile on the Settings screen when count > 0.
            composable(Screen.SyncIssues.route) {
                com.bizarreelectronics.crm.ui.screens.sync.SyncIssuesScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.GlobalSearch.route) {
                GlobalSearchScreen(
                    onResult = { type, id ->
                        when (type) {
                            "ticket" -> navController.navigate(Screen.TicketDetail.createRoute(id))
                            "customer" -> navController.navigate(Screen.CustomerDetail.createRoute(id))
                            "invoice" -> navController.navigate(Screen.InvoiceDetail.createRoute(id))
                            "inventory" -> navController.navigate(Screen.InventoryDetail.createRoute(id))
                        }
                    },
                )
            }
            composable(Screen.More.route) {
                MoreScreen(
                    onNavigate = { route -> navController.navigate(route) },
                    // CROSS41: the Log Out row invokes SettingsViewModel.logout,
                    // which clears auth + Room cache, then we pop back to Login.
                    onLogout = {
                        navController.navigate(Screen.Login.route) {
                            popUpTo(0) { inclusive = true }
                        }
                    },
                )
            }
            composable(Screen.Scanner.route) {
                BarcodeScanScreen(
                    onScanned = { code ->
                        // Return scanned code to previous screen via savedStateHandle
                        navController.previousBackStackEntry
                            ?.savedStateHandle
                            ?.set("scanned_barcode", code)
                        navController.popBackStack()
                    },
                    onBack = { navController.popBackStack() },
                )
            }

            // ─── Leads ───
            composable(Screen.Leads.route) {
                com.bizarreelectronics.crm.ui.screens.leads.LeadListScreen(
                    onLeadClick = { id -> navController.navigate(Screen.LeadDetail.createRoute(id)) },
                    onCreateClick = { navController.navigate(Screen.LeadCreate.route) },
                )
            }
            composable(Screen.LeadDetail.route) { backStackEntry ->
                val leadId = backStackEntry.arguments?.getString("id")?.toLongOrNull() ?: return@composable
                com.bizarreelectronics.crm.ui.screens.leads.LeadDetailScreen(
                    leadId = leadId,
                    onBack = { navController.popBackStack() },
                    onConverted = { ticketId ->
                        navController.navigate(Screen.TicketDetail.createRoute(ticketId)) {
                            popUpTo(Screen.Leads.route)
                        }
                    },
                )
            }
            composable(Screen.LeadCreate.route) {
                com.bizarreelectronics.crm.ui.screens.leads.LeadCreateScreen(
                    onBack = { navController.popBackStack() },
                    onCreated = { id ->
                        navController.navigate(Screen.LeadDetail.createRoute(id)) {
                            popUpTo(Screen.Leads.route)
                        }
                    },
                )
            }

            // ─── Appointments ───
            composable(Screen.Appointments.route) {
                com.bizarreelectronics.crm.ui.screens.leads.AppointmentListScreen(
                    onCreateClick = { navController.navigate(Screen.AppointmentCreate.route) },
                )
            }
            composable(Screen.AppointmentCreate.route) {
                com.bizarreelectronics.crm.ui.screens.leads.AppointmentCreateScreen(
                    onBack = { navController.popBackStack() },
                    onCreated = { _ -> navController.popBackStack() },
                )
            }

            // ─── Estimates ───
            composable(Screen.Estimates.route) { backStackEntry ->
                // AND-20260414-M7: EstimateDetailScreen writes `estimate_deleted = true`
                // to this back stack entry before popping. The list VM observes the
                // Room Flow so data is already fresh, but we clear the key so the
                // signal isn't left behind. If a future list needs a hard refresh
                // hook it can collect this same StateFlow.
                val estimateDeleted by backStackEntry.savedStateHandle
                    .getStateFlow("estimate_deleted", false)
                    .collectAsState()
                LaunchedEffect(estimateDeleted) {
                    if (estimateDeleted) {
                        backStackEntry.savedStateHandle["estimate_deleted"] = false
                    }
                }
                com.bizarreelectronics.crm.ui.screens.estimates.EstimateListScreen(
                    onEstimateClick = { id -> navController.navigate(Screen.EstimateDetail.createRoute(id)) },
                )
            }
            composable(Screen.EstimateDetail.route) { backStackEntry ->
                val estimateId = backStackEntry.arguments?.getString("id")?.toLongOrNull() ?: return@composable
                com.bizarreelectronics.crm.ui.screens.estimates.EstimateDetailScreen(
                    estimateId = estimateId,
                    onBack = { navController.popBackStack() },
                    onConverted = { ticketId ->
                        navController.navigate(Screen.TicketDetail.createRoute(ticketId)) {
                            popUpTo(Screen.Estimates.route)
                        }
                    },
                    onDeleted = {
                        // Signal to the list that something changed, then pop.
                        navController.previousBackStackEntry
                            ?.savedStateHandle
                            ?.set("estimate_deleted", true)
                        navController.popBackStack()
                    },
                )
            }

            // ─── Expenses ───
            composable(Screen.Expenses.route) {
                com.bizarreelectronics.crm.ui.screens.expenses.ExpenseListScreen(
                    onCreateClick = { navController.navigate(Screen.ExpenseCreate.route) },
                )
            }
            composable(Screen.ExpenseCreate.route) {
                com.bizarreelectronics.crm.ui.screens.expenses.ExpenseCreateScreen(
                    onBack = { navController.popBackStack() },
                    onCreated = { navController.popBackStack() },
                )
            }

            // ─── Inventory CRUD ───
            composable(Screen.InventoryCreate.route) {
                com.bizarreelectronics.crm.ui.screens.inventory.InventoryCreateScreen(
                    onBack = { navController.popBackStack() },
                    onCreated = { id ->
                        navController.navigate(Screen.InventoryDetail.createRoute(id)) {
                            popUpTo(Screen.Inventory.route)
                        }
                    },
                )
            }
            composable(Screen.InventoryEdit.route) {
                // itemId is read from SavedStateHandle by the ViewModel
                com.bizarreelectronics.crm.ui.screens.inventory.InventoryEditScreen(
                    onBack = { navController.popBackStack() },
                    onSaved = { navController.popBackStack() },
                )
            }

            // ─── SMS Templates ───
            composable(Screen.SmsTemplates.route) {
                com.bizarreelectronics.crm.ui.screens.settings.SmsTemplatesScreen(
                    onBack = { navController.popBackStack() },
                    onTemplateSelected = { body ->
                        navController.previousBackStackEntry
                            ?.savedStateHandle
                            ?.set("sms_template_body", body)
                        navController.popBackStack()
                    },
                )
            }
        }
        } // close §22.2 Row wrapper (NavigationRail + NavHost)
        } // close §17.10 KeyboardShortcutsHost wrapper
        }

        // §2.16 L399-L400 — session-timeout warning overlay. Renders as a Dialog
        // (modal layer above all content) when the idle countdown enters the
        // 60-second warning window. Placed outside the Column so it floats above
        // banners + NavHost without affecting the layout flow. Only active when
        // logged in; null-safe guard handles preview / test hosts that omit the dep.
        if (authPreferences?.isLoggedIn == true && sessionTimeout != null) {
            SessionTimeoutOverlay(
                sessionTimeout = sessionTimeout,
                onSignOut = {
                    authPreferences.clear()
                    // authCleared flow (above) will navigate to Screen.Login.
                },
            )
        }
    }
}

// ---------------------------------------------------------------------------
// MoreScreen — [P1] grouped BrandCard sections
// ---------------------------------------------------------------------------

/**
 * Represents a single navigable row in the MoreScreen.
 *
 * @param icon    Leading icon for the row.
 * @param label   Display label (sentence-case).
 * @param route   Navigation route string.
 */
private data class MoreItem(
    val icon: ImageVector,
    val label: String,
    val route: String,
)

/**
 * Represents a grouped section in the MoreScreen.
 *
 * @param title   Section heading in ALL-CAPS (sanctioned per §2 Navigation, display-condensed).
 * @param items   Rows belonging to this section.
 */
private data class MoreSection(
    val title: String,
    val items: List<MoreItem>,
)

@Composable
fun MoreScreen(
    onNavigate: (String) -> Unit,
    onLogout: () -> Unit = {},
    viewModel: SettingsViewModel = hiltViewModel(),
) {
    // Section groupings — sanctioned ALL-CAPS section labels (§2: "this IS a
    // sanctioned ALL-CAPS location" for section headers, headlineMedium / Inter
    // SemiBold caps used here since Wave 1 maps headlineMedium to Barlow Condensed
    // SemiBold which renders ALL-CAPS naturally; explicit uppercase on the string
    // ensures correct rendering regardless of font fallback).
    val sections = listOf(
        MoreSection(
            title = "CORE",
            items = listOf(
                MoreItem(Icons.Default.Search,    "Search",    Screen.GlobalSearch.route),
                MoreItem(Icons.Default.People,    "Customers", Screen.Customers.route),
                MoreItem(Icons.Default.Inventory, "Inventory", Screen.Inventory.route),
                MoreItem(Icons.Default.Receipt,   "Invoices",  Screen.Invoices.route),
            ),
        ),
        MoreSection(
            title = "SALES PIPELINE",
            items = listOf(
                MoreItem(Icons.Default.PersonAddAlt1, "Leads",        Screen.Leads.route),
                MoreItem(Icons.Default.Event,         "Appointments", Screen.Appointments.route),
                MoreItem(Icons.Default.Description,   "Estimates",    Screen.Estimates.route),
                MoreItem(Icons.Default.AttachMoney,   "Expenses",     Screen.Expenses.route),
            ),
        ),
        MoreSection(
            title = "OPERATIONS",
            items = listOf(
                MoreItem(Icons.Default.BarChart, "Reports",   Screen.Reports.route),
                MoreItem(Icons.Default.Group,    "Employees", Screen.Employees.route),
            ),
        ),
        MoreSection(
            title = "SETTINGS",
            items = listOf(
                // CROSS54: Settings section now disambiguates the inbox from
                // preferences. "Activity" routes to the notification-inbox list
                // (Screen.Notifications, route still "notifications" so FCM
                // deep-links and MainActivity's "notification" → "notifications"
                // mapping keep working). "Notifications" routes to the real
                // preferences page (Screen.NotificationSettings) so users who
                // tap Settings → Notifications land on push/email/quiet-hours
                // toggles — not an empty inbox.
                MoreItem(Icons.Default.Inbox,         "Activity",      Screen.Notifications.route),
                MoreItem(Icons.Default.Notifications, "Notifications", Screen.NotificationSettings.route),
                MoreItem(Icons.Default.Settings,      "Settings",      Screen.Settings.route),
            ),
        ),
    )

    // CROSS41: reusing SettingsViewModel so logout wiring is consistent with
    // the Settings > Sign Out row (clears Room cache + auth prefs in a single
    // atomic-ish sequence). authPreferences is exposed on the VM for the
    // header copy below.
    val auth = viewModel.authPreferences
    val firstName = auth.userFirstName?.takeIf { it.isNotBlank() }
    val lastName = auth.userLastName?.takeIf { it.isNotBlank() }
    val displayName = listOfNotNull(firstName, lastName).joinToString(" ")
        .ifBlank { auth.username ?: "Signed in" }
    val role = (auth.userRole ?: "").takeIf { it.isNotBlank() }
        ?.replaceFirstChar { it.uppercase() }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(WindowInsets.statusBars.asPaddingValues()),
        contentPadding = PaddingValues(bottom = 16.dp),
    ) {
        item {
            Text(
                "More",
                style = MaterialTheme.typography.headlineMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            )
        }

        // CROSS41: profile header card — avatar initial + display name + role.
        item {
            MoreProfileHeader(
                displayName = displayName,
                role = role,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 6.dp),
            )
        }

        sections.forEach { section ->
            item {
                MoreSectionCard(
                    section = section,
                    onNavigate = onNavigate,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 6.dp),
                )
            }
        }

        // CROSS41: destructive Log Out row at the bottom. Invokes the shared
        // SettingsViewModel.logout(onDone) which clears server session + local
        // Room cache + auth prefs, then the callback pops back to Login.
        item {
            MoreLogoutRow(
                onClick = { viewModel.logout(onLogout) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
            )
        }
    }
}

/**
 * CROSS41: Profile header card at the top of MoreScreen. Shows a purple
 * primary-container circle with the user's first initial, the full display
 * name, and (when available) their role. Kept static — no tap target — so
 * it mirrors the Settings screen "About" card for now. Promoting it to a
 * tap → profile edit is future work once the ProfileScreen route settles.
 */
@Composable
private fun MoreProfileHeader(
    displayName: String,
    role: String?,
    modifier: Modifier = Modifier,
) {
    BrandCard(modifier = modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val initial = displayName.firstOrNull { it.isLetter() }
                ?.uppercaseChar()?.toString() ?: "?"
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primaryContainer),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    initial,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    displayName,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                if (role != null) {
                    Text(
                        role,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

/**
 * CROSS41: destructive "Log Out" row rendered as a standalone BrandCard so
 * it visually separates from the navigation sections. Icon + label both use
 * the error color to telegraph the destructive action.
 */
@Composable
private fun MoreLogoutRow(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // D5-3: explicit ripple() + interactionSource so the destructive row
    // visibly flashes on tap. Without this, the row inside BrandCard felt
    // "ghosted" because the card surface suppressed LocalIndication.
    val interactionSource = remember { MutableInteractionSource() }
    BrandCard(modifier = modifier) {
        // D5-1: semantics(mergeDescendants) + Role.Button makes TalkBack treat the
        // whole row as one clickable labelled "Log Out" — the Icon below stays
        // contentDescription=null (decorative) because the sibling Text provides
        // the accessible name.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .semantics(mergeDescendants = true) { role = Role.Button }
                .clickable(
                    interactionSource = interactionSource,
                    indication = ripple(),
                    onClick = onClick,
                )
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.Logout,
                // decorative — parent Row labelled by sibling "Log Out" Text (D5-1)
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(22.dp),
            )
            Text(
                text = "Log Out",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

/**
 * A single grouped card section in [MoreScreen].
 * Section title uses [MaterialTheme.typography.headlineMedium] (Barlow Condensed via
 * Wave 1 typography) for the ALL-CAPS sanctioned section label.
 * Rows are separated by a 1dp divider at [MaterialTheme.colorScheme.outline] × 0.4f alpha.
 * Each row has a teal [Icons.Default.ChevronRight] trailing icon.
 */
@Composable
private fun MoreSectionCard(
    section: MoreSection,
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier) {
        // Section label: ALL-CAPS in headlineMedium (Barlow Condensed SemiBold via
        // Wave 1 Typography), muted so it reads as a label not a heading.
        Text(
            text = section.title,
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 4.dp, end = 4.dp, bottom = 4.dp),
        )

        BrandCard {
            section.items.forEachIndexed { index, item ->
                MoreRowItem(
                    item = item,
                    onClick = { onNavigate(item.route) },
                )
                // 1dp outline divider between rows (not after the last row)
                if (index < section.items.lastIndex) {
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                        thickness = 1.dp,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                }
            }
        }
    }
}

/**
 * A single row inside a [MoreSectionCard].
 * Leading icon in [MaterialTheme.colorScheme.onSurfaceVariant], label in body-sans,
 * trailing teal chevron to indicate navigation.
 */
@Composable
private fun MoreRowItem(
    item: MoreItem,
    onClick: () -> Unit,
) {
    // D5-3: explicit ripple() + interactionSource so each row in the More
    // section flashes on tap. Prior bare .clickable in a BrandCard context
    // produced no ripple — the card's surface drew over LocalIndication.
    val interactionSource = remember { MutableInteractionSource() }
    // D5-1: semantics(mergeDescendants) + Role.Button collapses leading icon +
    // label text + trailing chevron into a single TalkBack focus item named by
    // item.label — both Icons below can safely stay contentDescription=null.
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { role = Role.Button }
            .clickable(
                interactionSource = interactionSource,
                indication = ripple(),
                onClick = onClick,
            )
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            imageVector = item.icon,
            // decorative — parent Row labelled by sibling item.label Text (D5-1)
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(22.dp),
        )
        Text(
            text = item.label,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f),
        )
        // Teal chevron — secondary color = teal via Wave 1 palette.
        // decorative — purely visual navigation affordance (D5-1)
        Icon(
            imageVector = Icons.Default.ChevronRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.secondary,
            modifier = Modifier.size(20.dp),
        )
    }
}
