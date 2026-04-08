package com.bizarreelectronics.crm.ui.navigation

import android.net.Uri
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
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
import com.bizarreelectronics.crm.ui.screens.employees.EmployeeListScreen
import com.bizarreelectronics.crm.ui.screens.settings.SettingsScreen
import com.bizarreelectronics.crm.ui.screens.search.GlobalSearchScreen
import com.bizarreelectronics.crm.ui.components.shared.OfflineBanner
import com.bizarreelectronics.crm.util.NetworkMonitor
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
    data object Notifications : Screen("notifications")
    data object Settings : Screen("settings")
    data object GlobalSearch : Screen("search")
    data object Scanner : Screen("scanner")
    data object More : Screen("more")
}

data class BottomNavItem(
    val screen: Screen,
    val label: String,
    val icon: @Composable () -> Unit,
)

@Composable
fun AppNavGraph(authPreferences: AuthPreferences? = null, networkMonitor: NetworkMonitor? = null) {
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
    )

    // Determine if we should show the bottom nav
    val showBottomNav = currentRoute != null &&
            currentRoute != Screen.Login.route &&
            !currentRoute.startsWith("tickets/") &&
            currentRoute != Screen.TicketCreate.route &&
            !currentRoute.startsWith("customers/") &&
            currentRoute != Screen.CustomerCreate.route &&
            !currentRoute.startsWith("invoices/") &&
            !currentRoute.startsWith("inventory/") &&
            !currentRoute.startsWith("messages/") &&
            !currentRoute.startsWith("checkout/") &&
            !currentRoute.startsWith("ticket-success/") &&
            currentRoute != Screen.Scanner.route

    val bottomNavItems = listOf(
        BottomNavItem(Screen.Dashboard, "Dashboard") { Icon(Icons.Default.Home, "Dashboard") },
        BottomNavItem(Screen.Tickets, "Tickets") { Icon(Icons.Default.ConfirmationNumber, "Tickets") },
        BottomNavItem(Screen.Pos, "POS") { Icon(Icons.Default.PointOfSale, "POS") },
        BottomNavItem(Screen.Messages, "Messages") { Icon(Icons.Default.Chat, "Messages") },
        BottomNavItem(Screen.More, "More") { Icon(Icons.Default.MoreHoriz, "More") },
    )

    Scaffold(
        bottomBar = {
            if (showBottomNav) {
                NavigationBar {
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
        val isOffline = networkMonitor?.let {
            val online by it.isOnline.collectAsState(initial = true)
            !online
        } ?: false

        Column(modifier = Modifier.padding(padding)) {
            OfflineBanner(isOffline = isOffline)

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
                )
            }
            composable(Screen.Messages.route) {
                SmsListScreen(
                    onConversationClick = { phone -> navController.navigate(Screen.SmsThread.createRoute(phone)) },
                )
            }
            composable(Screen.SmsThread.route) { backStackEntry ->
                val phone = backStackEntry.arguments?.getString("phone") ?: return@composable
                SmsThreadScreen(
                    phone = phone,
                    onBack = { navController.popBackStack() },
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
            composable(Screen.Employees.route) {
                EmployeeListScreen()
            }
            composable(Screen.Settings.route) {
                SettingsScreen(
                    onLogout = {
                        navController.navigate(Screen.Login.route) {
                            popUpTo(0) { inclusive = true }
                        }
                    },
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
        }
        }
    }
}

@Composable
fun MoreScreen(onNavigate: (String) -> Unit) {
    Column(modifier = Modifier.fillMaxSize().padding(WindowInsets.statusBars.asPaddingValues())) {
        Text(
            "More",
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        )
        val items = listOf(
            Triple(Icons.Default.Search, "Search", Screen.GlobalSearch.route),
            Triple(Icons.Default.People, "Customers", Screen.Customers.route),
            Triple(Icons.Default.Inventory, "Inventory", Screen.Inventory.route),
            Triple(Icons.Default.Receipt, "Invoices", Screen.Invoices.route),
            Triple(Icons.Default.BarChart, "Reports", Screen.Reports.route),
            Triple(Icons.Default.Group, "Employees", Screen.Employees.route),
            Triple(Icons.Default.Notifications, "Notifications", Screen.Notifications.route),
            Triple(Icons.Default.Settings, "Settings", Screen.Settings.route),
        )
        items.forEach { (icon, label, route) ->
            NavigationDrawerItem(
                icon = { Icon(icon, null) },
                label = { Text(label) },
                selected = false,
                onClick = { onNavigate(route) },
                modifier = Modifier.padding(horizontal = 12.dp),
            )
        }
    }
}
