package com.bizarreelectronics.crm.ui.navigation

import android.net.Uri
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.*
import androidx.navigation.navArgument
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.ui.screens.auth.LoginScreen
import com.bizarreelectronics.crm.ui.screens.dashboard.DashboardScreen
import com.bizarreelectronics.crm.ui.screens.tickets.TicketListScreen
import com.bizarreelectronics.crm.ui.screens.tickets.TicketDetailScreen
import com.bizarreelectronics.crm.ui.screens.customers.CustomerListScreen
import com.bizarreelectronics.crm.ui.screens.customers.CustomerDetailScreen
import com.bizarreelectronics.crm.ui.screens.inventory.InventoryListScreen
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
import com.bizarreelectronics.crm.ui.screens.settings.ProfileScreen
import com.bizarreelectronics.crm.ui.screens.settings.SettingsScreen
import com.bizarreelectronics.crm.ui.screens.settings.SettingsViewModel
import com.bizarreelectronics.crm.ui.screens.search.GlobalSearchScreen
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.sync.SyncManager
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.OfflineBanner
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import java.util.Locale
import javax.inject.Inject

sealed class Screen(val route: String) {
    data object Login : Screen("login")
    data object Dashboard : Screen("dashboard")
    data object Tickets : Screen("tickets")
    data object TicketDetail : Screen("tickets/{id}") {
        fun createRoute(id: Long) = "tickets/$id"
    }
    data object TicketCreate : Screen("ticket-create")
    data object TicketDeviceEdit : Screen("tickets/{ticketId}/devices/{deviceId}") {
        fun createRoute(ticketId: Long, deviceId: Long) = "tickets/$ticketId/devices/$deviceId"
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
}

data class BottomNavItem(
    val screen: Screen,
    val label: String,
    val icon: @Composable () -> Unit,
)

@Composable
fun AppNavGraph(
    authPreferences: AuthPreferences? = null,
    serverReachabilityMonitor: ServerReachabilityMonitor? = null,
    syncQueueDao: SyncQueueDao? = null,
    syncManager: SyncManager? = null,
) {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    // Observe auth expiry: when AuthInterceptor fails to refresh and clears
    // prefs, navigate the user back to the login screen.
    LaunchedEffect(authPreferences) {
        authPreferences?.authCleared?.collect {
            navController.navigate(Screen.Login.route) {
                popUpTo(0) { inclusive = true }
            }
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
            currentRoute != Screen.TicketCreate.route &&
            currentRoute != Screen.ClockInOut.route &&
            currentRoute != Screen.EmployeeCreate.route &&
            !currentRoute.startsWith("customers/") &&
            currentRoute != Screen.CustomerCreate.route &&
            !currentRoute.startsWith("invoices/") &&
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
            currentRoute != Screen.Scanner.route

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
            if (showBottomNav) {
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

            NavHost(
                navController = navController,
                startDestination = if (authPreferences?.isLoggedIn == true && !authPreferences.serverUrl.isNullOrBlank())
                    Screen.Dashboard.route else Screen.Login.route,
                modifier = Modifier.weight(1f),
                enterTransition = { fadeIn(animationSpec = tween(200)) },
                exitTransition = { fadeOut(animationSpec = tween(200)) },
                popEnterTransition = { fadeIn(animationSpec = tween(200)) },
                popExitTransition = { fadeOut(animationSpec = tween(200)) },
            ) {
            composable(Screen.Login.route) {
                LoginScreen(onLoginSuccess = {
                    navController.navigate(Screen.Dashboard.route) {
                        popUpTo(Screen.Login.route) { inclusive = true }
                    }
                })
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
                    onEditDevice = { deviceId ->
                        navController.navigate(Screen.TicketDeviceEdit.createRoute(ticketId, deviceId))
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
            composable(Screen.TicketCreate.route) {
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
                    // CROSS47: routes to the ticket wizard. Pre-seed of the
                    // customer is tracked as CROSS47-seed (wizard currently
                    // drops the customerId parameter). Once the wizard reads
                    // a nav arg we flip this to createRoute(customerId).
                    onCreateTicket = { _ -> navController.navigate(Screen.TicketCreate.route) },
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
            composable(Screen.Checkout.route) { backStackEntry ->
                val ticketId = backStackEntry.arguments?.getString("ticketId")?.toLongOrNull() ?: return@composable
                CheckoutScreen(
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
                    onNotificationClick = { type, id ->
                        when {
                            type == "ticket" && id != null -> navController.navigate(Screen.TicketDetail.createRoute(id))
                            type == "invoice" && id != null -> navController.navigate(Screen.InvoiceDetail.createRoute(id))
                            // SMS notifications don't have a direct detail route
                        }
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
                    refreshTrigger = employeeCreated,
                    onRefreshConsumed = {
                        backStackEntry.savedStateHandle["employee_created"] = false
                    },
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
                )
            }
            composable(Screen.Profile.route) {
                ProfileScreen(
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
                MoreItem(Icons.Default.Notifications, "Notifications", Screen.Notifications.route),
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
    BrandCard(modifier = modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onClick)
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.Logout,
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
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            imageVector = item.icon,
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
        // Teal chevron — secondary color = teal via Wave 1 palette
        Icon(
            imageVector = Icons.Default.ChevronRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.secondary,
            modifier = Modifier.size(20.dp),
        )
    }
}
