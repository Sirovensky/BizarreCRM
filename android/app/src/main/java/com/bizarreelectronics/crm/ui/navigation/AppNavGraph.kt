package com.bizarreelectronics.crm.ui.navigation

import android.content.Context
import android.net.Uri
import androidx.compose.animation.*
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionLayout
import androidx.compose.ui.platform.LocalContext
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
import com.bizarreelectronics.crm.ui.screens.activity.ActivityFeedScreen
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
import com.bizarreelectronics.crm.ui.screens.invoices.InvoiceAgingScreen
import com.bizarreelectronics.crm.ui.screens.invoices.InvoiceDetailScreen
import com.bizarreelectronics.crm.ui.screens.invoices.InvoiceListScreen
import com.bizarreelectronics.crm.ui.screens.inventory.BarcodeScanScreen
import com.bizarreelectronics.crm.ui.screens.inventory.InventoryDetailScreen
import com.bizarreelectronics.crm.ui.screens.pos.PosEntryScreen
import com.bizarreelectronics.crm.ui.screens.pos.PosCartScreen
import com.bizarreelectronics.crm.ui.screens.pos.PosSplitCartScreen
import com.bizarreelectronics.crm.ui.screens.pos.PosTenderScreen
import com.bizarreelectronics.crm.ui.screens.pos.PosReceiptScreen
import com.bizarreelectronics.crm.ui.screens.pos.StoreCreditPaymentScreen
import com.bizarreelectronics.crm.ui.screens.communications.SmsListScreen
import com.bizarreelectronics.crm.ui.screens.communications.SmsThreadScreen
import com.bizarreelectronics.crm.ui.screens.notifications.NotificationListScreen
import com.bizarreelectronics.crm.ui.screens.reports.ReportsScreen
import com.bizarreelectronics.crm.ui.screens.employees.ClockInOutScreen
import com.bizarreelectronics.crm.ui.screens.employees.EmployeeListScreen
import com.bizarreelectronics.crm.ui.screens.tickets.TicketDeviceEditScreen
import com.bizarreelectronics.crm.ui.screens.camera.PhotoCaptureScreen
import com.bizarreelectronics.crm.ui.screens.hardware.CameraCaptureScreen
import com.bizarreelectronics.crm.ui.screens.hardware.DocumentScanScreen
import com.bizarreelectronics.crm.ui.screens.settings.hardware.HardwareSettingsScreen
import com.bizarreelectronics.crm.ui.screens.settings.hardware.PrinterDiscoveryScreen
import com.bizarreelectronics.crm.ui.screens.settings.ActiveSessionsScreen
import com.bizarreelectronics.crm.ui.screens.settings.ChangePasswordScreen
import com.bizarreelectronics.crm.ui.screens.settings.ForgotPinScreen
import com.bizarreelectronics.crm.ui.screens.settings.DiagnosticsScreen
import com.bizarreelectronics.crm.ui.screens.settings.PasskeyScreen
import com.bizarreelectronics.crm.ui.screens.settings.RecoveryCodesScreen
import com.bizarreelectronics.crm.ui.screens.settings.TwoFactorFactorsScreen
import com.bizarreelectronics.crm.ui.screens.settings.RateLimitBucketsScreen
import com.bizarreelectronics.crm.ui.screens.settings.LanguageScreen
import com.bizarreelectronics.crm.ui.screens.settings.NotificationSettingsScreen
import com.bizarreelectronics.crm.ui.screens.settings.ProfileScreen
import com.bizarreelectronics.crm.ui.screens.settings.SecurityScreen
import com.bizarreelectronics.crm.ui.screens.settings.SettingsScreen
import com.bizarreelectronics.crm.ui.screens.settings.SettingsViewModel
import com.bizarreelectronics.crm.ui.screens.settings.ThemeScreen
import com.bizarreelectronics.crm.ui.screens.settings.SwitchUserScreen
import com.bizarreelectronics.crm.ui.screens.settings.SharedDeviceScreen
import com.bizarreelectronics.crm.ui.screens.settings.AppearanceScreen
import com.bizarreelectronics.crm.ui.screens.settings.DisplaySettingsScreen
import com.bizarreelectronics.crm.ui.screens.settings.SecuritySummaryScreen
import com.bizarreelectronics.crm.ui.screens.tv.TvQueueBoardScreen
import com.bizarreelectronics.crm.ui.screens.bench.BenchTabScreen
import com.bizarreelectronics.crm.ui.screens.settings.DeviceTemplatesScreen
import com.bizarreelectronics.crm.ui.screens.settings.RepairPricingScreen
import com.bizarreelectronics.crm.ui.screens.pricingcatalog.DeviceCatalogScreen
import com.bizarreelectronics.crm.ui.screens.settings.TicketSettingsScreen
import com.bizarreelectronics.crm.ui.screens.settings.PosSettingsScreen
import com.bizarreelectronics.crm.ui.screens.settings.SmsSettingsScreen
import com.bizarreelectronics.crm.ui.screens.settings.BusinessInfoScreen
import com.bizarreelectronics.crm.ui.screens.auth.StaffPickerScreen
import com.bizarreelectronics.crm.ui.screens.search.GlobalSearchScreen
import com.bizarreelectronics.crm.ui.screens.setup.SetupWizardScreen
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.sync.SyncManager
import com.bizarreelectronics.crm.ui.components.ClockDriftBanner
import com.bizarreelectronics.crm.ui.components.RateLimitBanner
import com.bizarreelectronics.crm.ui.components.SessionTimeoutOverlay
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.OfflineBanner
import com.bizarreelectronics.crm.util.ClockDrift
import com.bizarreelectronics.crm.util.DeepLinkBus
import com.bizarreelectronics.crm.util.NetworkMonitor
import com.bizarreelectronics.crm.util.RateLimiter
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.util.SessionTimeout
import com.bizarreelectronics.crm.ui.screens.memberships.MembershipListScreen
import com.bizarreelectronics.crm.ui.screens.cash.CashRegisterScreen
import com.bizarreelectronics.crm.ui.screens.giftcards.GiftCardScreen
import com.bizarreelectronics.crm.ui.screens.audit.AuditLogsScreen
import com.bizarreelectronics.crm.ui.screens.importdata.DataImportScreen
import com.bizarreelectronics.crm.ui.screens.exportdata.DataExportScreen
import com.bizarreelectronics.crm.ui.commandpalette.CommandPaletteScreen
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import java.util.Locale
import javax.inject.Inject

sealed class Screen(val route: String) {
    data object Login : Screen("login") {
        // §2.7 L330 — nav route variant carrying an invite token from
        // bizarrecrm.com/setup/:token. The base route "login" remains the
        // default start destination; this factory is used only when a deep
        // link delivers a token.
        fun withSetupToken(token: String) = "login?setupToken=${android.net.Uri.encode(token)}"
    }
    data object Dashboard : Screen("dashboard")
    data object Tickets : Screen("tickets")
    data object TicketDetail : Screen("tickets/{id}") {
        fun createRoute(id: Long) = "tickets/$id"
    }
    // Screen.TicketCreate removed 2026-04-24 — replaced by Screen.CheckInEntry
    // (the new 6-step repair check-in flow). All callers migrated.
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
    /** Tag-filtered customer list. [tag] is URI-encoded in [createRoute]. */
    data object CustomersFilteredByTag : Screen("customers?tag={tag}") {
        fun createRoute(tag: String) = "customers?tag=${Uri.encode(tag)}"
    }
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
    data object InvoicesAging : Screen("invoices/aging")
    data object Pos : Screen("pos")
    data object PosCart : Screen("pos/cart")
    data object PosTender : Screen("pos/tender")
    // TASK-6: split cart stub
    data object PosSplitCart : Screen("pos/split-cart")
    // AUDIT-030: dedicated screen for store-credit payment path tile.
    data object StoreCreditPayment : Screen("pos/store-credit-payment")
    data object PosReceipt : Screen("pos/receipt/{orderId}") {
        fun createRoute(orderId: String) = "pos/receipt/${Uri.encode(orderId)}"
    }
    // 6-step repair check-in (Symptoms → Details → Damage → Diagnostic →
    // Quote → Sign). Requires a customer + device pre-attached; callers
    // unable to provide both should route through `Screen.Pos` first
    // (its path-picker attaches customer, then opens device picker).
    data object CheckIn : Screen("checkin/{customerId}/{deviceId}?customerName={customerName}&deviceName={deviceName}") {
        fun createRoute(customerId: Long, deviceId: Long, customerName: String, deviceName: String): String =
            "checkin/$customerId/$deviceId?customerName=${Uri.encode(customerName)}&deviceName=${Uri.encode(deviceName)}"
    }
    /** Pre-step that collects customer + device info before launching [CheckIn]. */
    /**
     * customerId arg sentinels:
     *   null      → no pre-fill; cashier picks customer in step 1
     *   0L        → walk-in pre-fill (skip step 1, jump to device step)
     *   >0L       → real customer pre-fill
     */
    data object CheckInEntry : Screen("checkin-entry?customerId={customerId}") {
        /**
         * Optional pre-fill: when the entry is launched from a customer
         * detail screen, the customer is already known — skip re-searching.
         * Bare route (no customerId) still works via default.
         */
        fun createRoute(customerId: Long? = null): String =
            if (customerId != null) "checkin-entry?customerId=$customerId" else "checkin-entry"
    }
    // POS-AUDIT-041: Screen.Checkout + Screen.TicketSuccess removed — both were
    // Phase-3 stubs superseded by the check-in flow. Screen files deleted.
    data object Messages : Screen("messages")
    data object SmsThread : Screen("messages/{phone}") {
        fun createRoute(phone: String) = "messages/${Uri.encode(phone)}"
    }
    data object Reports : Screen("reports")

    // §15 L1722 — sub-report destinations (SegmentedButton routing)
    data object ReportSales : Screen("reports/sales")
    data object ReportTickets : Screen("reports/tickets")
    data object ReportInventory : Screen("reports/inventory")
    data object ReportTax : Screen("reports/tax")
    data object ReportCustom : Screen("reports/custom")
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
    data object AppointmentDetail : Screen("appointments/{appointmentId}") {
        fun createRoute(id: Long) = "appointments/$id"
    }

    // Estimates
    data object Estimates : Screen("estimates")
    data object EstimateDetail : Screen("estimates/{id}") {
        fun createRoute(id: Long) = "estimates/$id"
    }
    data object EstimateCreate : Screen("estimate-create?leadId={leadId}") {
        fun createRoute(leadId: Long? = null): String =
            if (leadId != null) "estimate-create?leadId=$leadId" else "estimate-create"
    }

    // Expenses
    data object Expenses : Screen("expenses")
    data object ExpenseCreate : Screen("expense-create")
    data object ExpenseDetail : Screen("expenses/{id}") {
        fun createRoute(id: Long) = "expenses/$id"
    }

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

    // §1.2 [plan:L258] — Rate-limit bucket state viewer. DEBUG builds only.
    data object RateLimitBuckets : Screen("settings/rate-limit-buckets")

    // §37 — Marketing & Growth: campaign list/create/send + segment builder.
    data object Marketing : Screen("marketing")

    // §28 / §32 About + diagnostics — copy-bundle for support tickets.
    data object About : Screen("settings/about")

    // §2.1 — Setup-status gate: probes GET /auth/setup-status before showing
    // the login form. Shown when a serverUrl is saved but no session exists.
    data object SetupStatusGate : Screen("auth/setup-gate")

    // §2.9 — Change-password screen (authenticated; reachable from Security sub-screen).
    data object ChangePassword : Screen("settings/security/change-password")

    // §2.11 — Active sessions list + revoke (reachable from Security sub-screen).
    data object ActiveSessions : Screen("settings/active-sessions")

    // §2.5 — Switch User (shared device): PIN entry to switch active identity.
    // Entry point: Settings > "Switch user" row (and TODO: long-press avatar in top bar).
    data object SwitchUser : Screen("settings/switch-user")

    // §2.14 [plan:L369-L378] — Shared-Device Mode settings sub-screen.
    // Gated behind manager PIN at the call site in AppNavGraph.
    data object SharedDevice : Screen("settings/shared-device")

    // §2.14 [plan:L369-L378] — Staff picker (kiosk lock screen).
    // Shown automatically when sharedDeviceModeEnabled=true and the inactivity
    // threshold has elapsed. Replaces the single-user PIN gate in shared mode.
    data object StaffPicker : Screen("auth/staff-picker")

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

    // §2.19 — Recovery codes settings screen (generate / display / print / email).
    data object RecoveryCodes : Screen("settings/security/recovery-codes")

    // §2.18 L420 — Manage 2FA factors screen (list enrolled, enroll TOTP/SMS; passkey/HW stubs).
    data object TwoFactorFactors : Screen("settings/security/2fa-factors")

    // §2.22 L463 — Passkey management screen (enroll, list, remove passkeys + hardware keys).
    data object Passkeys : Screen("settings/security/passkeys")

    // §2.10 [plan:L343] — 13-step first-run tenant onboarding wizard.
    // Reachable from:
    //   1. SetupStatusGateScreen when GET /auth/setup-status returns needsSetup=true.
    //   2. Deep link bizarrecrm://setup (carries a setup token from a tenant-invite email).
    data object Setup : Screen("setup/wizard")

    // §2.15 L387-L388 — Forgot-PIN self-service email reset.
    // Pre-auth; shown when the user taps "Forgot PIN?" on the lock screen.
    // Deep-link token (bizarrecrm://forgot-pin/<token>) is handled via
    // DeepLinkBus.pendingForgotPinToken; no manifest <data> entry needed for MVP.
    data object ForgotPin : Screen("auth/forgot-pin")

    // §3.13 L565–L567 — Display sub-screen (TV queue board + keep-screen-on toggle).
    data object DisplaySettings : Screen("settings/display")

    // §3.19 L613–L616 — Appearance / dashboard density picker.
    data object Appearance : Screen("settings/appearance")

    // §4.9 L756 — Bench tab: list of current technician's active bench tickets.
    data object Bench : Screen("bench")

    // §4.9 L762 — Device templates Settings sub-screen.
    data object DeviceTemplates : Screen("settings/device-templates")

    // §4.9 L766 — Repair pricing catalog Settings sub-screen.
    data object RepairPricing : Screen("settings/repair-pricing")

    // §44.3 — Device catalog browse + admin add screen.
    data object DeviceCatalog : Screen("settings/device-catalog")

    // §3.13 L565–L567 — Full-screen TV queue board for in-shop display mode.
    data object TvQueueBoard : Screen("tv/queue")

    // §17.1-§17.5 — Hardware screens (CameraX, barcode, document scan, printers, terminal)
    data object CameraCapture : Screen("hardware/camera/{ticketId}/{deviceId}") {
        fun createRoute(ticketId: Long, deviceId: Long) = "hardware/camera/$ticketId/$deviceId"
    }
    data object DocumentScan : Screen("hardware/document-scan")
    data object HardwareSettings : Screen("settings/hardware")
    data object PrinterDiscovery : Screen("settings/hardware/printers")

    // §36 L585–L588 — Morning-open checklist (staff role, shown once per day).
    data object MorningChecklist : Screen("morning/checklist")

    // §3.16 L592-L599 — Full-screen Activity Feed with filters, reactions, infinite scroll.
    data object ActivityFeed : Screen("activity/feed")

    // plan:L2009-L2014 — Security Summary consolidated view.
    // Deep link: bizarrecrm://settings/security-summary
    data object SecuritySummary : Screen("settings/security/summary")

    // §41 — Payment Links (create + list)
    data object PaymentLinks : Screen("payment-links")
    data object PaymentLinkCreate : Screen("payment-links/create")

    // §42 — Voice / Calls (list + detail)
    data object Calls : Screen("calls")
    data object CallDetail : Screen("calls/{id}") {
        fun createRoute(id: Long) = "calls/$id"
    }

    // §38 — Memberships / Loyalty list screen.
    data object Memberships : Screen("memberships")

    // §39 — Cash Register / Z-Report screen.
    data object CashRegister : Screen("cash-register")

    // §40 — Gift Cards / Store Credit screen.
    data object GiftCards : Screen("gift-cards")

    // §47 — Team Chat rooms list + thread screens.
    data object TeamChat : Screen("team-chat")
    data object TeamChatThread : Screen("team-chat/{roomId}") {
        fun createRoute(roomId: String, roomName: String = "") =
            "team-chat/${android.net.Uri.encode(roomId)}?roomName=${android.net.Uri.encode(roomName)}"
    }

    // §48 — Goals, Performance Reviews & Time Off
    data object Goals : Screen("goals")
    data object PerformanceReviews : Screen("performance-reviews")
    data object TimeOffRequest : Screen("time-off-request")
    data object TimeOffList : Screen("time-off-list")

    // §14.6 — Team shifts / weekly schedule
    data object ShiftsSchedule : Screen("shifts-schedule")

    // §14.7 — Employee leaderboard
    data object Leaderboard : Screen("leaderboard")

    // §14.4 — Role management (admin)
    data object RoleManagement : Screen("role-management")

    // §52 — Audit Logs (admin-only)
    data object AuditLogs : Screen("audit-logs")

    // §50 — Data Import (admin-only)
    data object DataImport : Screen("data-import")

    // §51 — Data Export (manager+)
    data object DataExport : Screen("data-export")

    // §54 — Command Palette (overlay; not a real nav destination, but registered
    // so Ctrl+K handling in AppNavGraph can check against it)
    data object CommandPalette : Screen("command-palette")

    // §19.7 — Ticket settings sub-screen (defaults, visibility, requirements)
    data object TicketSettings : Screen("settings/tickets")

    // §19.8 — POS / payment settings sub-screen
    data object PosSettings : Screen("settings/pos")

    // §19.9 — SMS settings sub-screen
    data object SmsSettings : Screen("settings/sms")

    // §19.19 — Business info sub-screen
    data object BusinessInfo : Screen("settings/business-info")
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
private fun mapResolvedRoute(raw: String): String? = when {
    // External H1 contract routes → internal nav destinations
    raw == "ticket/new"   -> Screen.CheckInEntry.route
    raw == "customer/new" -> Screen.CustomerCreate.route
    raw == "scan"         -> Screen.Scanner.route
    // §2.7 L330 — setup invite: "login?setupToken=<encoded>" must navigate
    // to the Login composable before the user is authenticated. Returned
    // as-is; the auth gate in the collector is bypassed for this prefix.
    raw.startsWith("login?setupToken=") -> raw
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
    networkMonitor: NetworkMonitor? = null,
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

    // §54 — Command palette overlay state. Toggled by Ctrl+K (keyboard) or a
    // FAB wired at the call site. Palette is a Dialog overlay — not a nav
    // destination — so we keep the boolean here rather than in the back-stack.
    var showCommandPalette by remember { mutableStateOf(false) }

    // POS session reset confirmation. When the cashier is already inside the
    // POS sub-flow (cart / tender / receipt) and taps the POS bottom-nav tab,
    // we prompt: 'Continue' (pop back to entry, keep session) vs 'Start over'
    // (resetSession + nav to entry). Without this prompt, the bottom nav's
    // restoreState=true just put them right back on the cart.
    var showPosResetDialog by remember { mutableStateOf(false) }
    val posCoordinator = remember(navController) {
        runCatching {
            val ctx = navController.context
            val entry = dagger.hilt.android.EntryPointAccessors.fromApplication(
                ctx.applicationContext,
                com.bizarreelectronics.crm.ui.navigation.PosCoordinatorEntryPoint::class.java,
            )
            entry.posCoordinator()
        }.getOrNull()
    }

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

    val isLoggedIn by (authPreferences?.isLoggedInFlow
        ?: kotlinx.coroutines.flow.MutableStateFlow(false))
        .collectAsStateWithLifecycle()

    LaunchedEffect(isLoggedIn) {
        if (!isLoggedIn && currentRoute != null && !currentRoute.startsWith("login") && currentRoute != Screen.Login.route) {
            navController.navigate(Screen.Login.route) {
                popUpTo(0) { inclusive = true }
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
    //
    // §2.7 L330 — exception: setup-token routes are pre-auth; they navigate
    // to the Login composable so the invite token is passed in before the
    // user has a session. We bypass the isLoggedIn gate for this prefix only.
    LaunchedEffect(deepLinkBus, authPreferences?.isLoggedIn) {
        deepLinkBus?.pendingRoute?.collect { raw ->
            if (raw == null) return@collect
            val isSetupToken = raw.startsWith("login?setupToken=")
            // §2.15 L387 — forgot-pin is pre-auth (user has no active session
            // when they're locked behind the PIN gate). Bypass the isLoggedIn
            // check so the route resolves while the session is still valid but
            // the PIN gate was active.
            val isForgotPin = raw == Screen.ForgotPin.route
            if (!isSetupToken && !isForgotPin && authPreferences?.isLoggedIn != true) return@collect
            val dest = mapResolvedRoute(raw)
            if (dest != null) {
                navController.navigate(dest) {
                    if (isSetupToken) {
                        // Replace the current back-stack entry so the user
                        // doesn't land back on the bare Login after pressing
                        // back from the Register step.
                        popUpTo("login?setupToken={setupToken}") { inclusive = true }
                    }
                }
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
    val showBottomNav = isLoggedIn &&
            currentRoute != null &&
            (currentRoute?.startsWith("login") != true) &&
            !currentRoute.startsWith("tickets/") &&
            // CROSS47-seed: the registered route is now
            // `ticket-create?customerId={customerId}`, so an exact equality
            // check against the bare `ticket-create` literal would never hit
            // and the wizard would wrongly show the bottom-nav. Match by
            // prefix instead.
            !currentRoute.startsWith(Screen.CheckInEntry.route) &&
            !currentRoute.startsWith("checkin/") &&
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
            !currentRoute.startsWith("leads/") &&
            currentRoute != Screen.LeadCreate.route &&
            currentRoute != Screen.AppointmentCreate.route &&
            !currentRoute.startsWith("appointments/") &&
            !currentRoute.startsWith("estimates/") &&
            currentRoute != Screen.ExpenseCreate.route &&
            !currentRoute.startsWith("settings/") &&
            currentRoute != Screen.Scanner.route &&
            // POS-AUDIT-032: Cart, Tender, Receipt, and StoreCreditPayment are
            // full-screen POS flows; bottom nav must not show on any of them.
            currentRoute != Screen.PosCart.route &&
            currentRoute != Screen.PosTender.route &&
            currentRoute != Screen.PosSplitCart.route &&
            !currentRoute.startsWith("pos/receipt/") &&
            currentRoute != Screen.StoreCreditPayment.route &&
            // AUD-20260414-M5: Sync Issues is a modal-ish diagnostic screen
            // reached from Settings, so hide the bottom bar like other
            // non-root detail routes.
            currentRoute != Screen.SyncIssues.route &&
            // §2.8 — pre-auth password-reset screens hide the bottom bar
            currentRoute != Screen.ForgotPassword.route &&
            !currentRoute.startsWith("auth/reset-password/") &&
            currentRoute != Screen.BackupCodeRecovery.route &&
            // §2.15 L387 — forgot-PIN screen is pre-auth; hide bottom bar
            currentRoute != Screen.ForgotPin.route &&
            // §2.1 — setup-status gate is a pre-auth transient screen
            currentRoute != Screen.SetupStatusGate.route &&
            // §2.10 [plan:L343] — setup wizard hides the bottom bar (full-screen flow)
            currentRoute != Screen.Setup.route &&
            // §3.13 L565–L567 — TV queue board is full-screen; no bottom bar.
            currentRoute != Screen.TvQueueBoard.route &&
            // §17.1-§17.5 — hardware screens are full-frame; no bottom bar.
            !currentRoute.startsWith("hardware/") &&
            currentRoute != Screen.HardwareSettings.route &&
            currentRoute != Screen.PrinterDiscovery.route &&
            // §4.9 L756 — bench tab and settings sub-screens hide the bottom bar
            currentRoute != Screen.Bench.route

    val bottomNavItems = listOf(
        BottomNavItem(Screen.Dashboard, "Dashboard") { Icon(Icons.Default.Home, "Dashboard") },
        BottomNavItem(Screen.Tickets, "Tickets") { Icon(Icons.Default.ConfirmationNumber, "Tickets") },
        BottomNavItem(Screen.Pos, "POS") { Icon(Icons.Default.PointOfSale, "POS") },
        BottomNavItem(Screen.Messages, "Messages") { Icon(Icons.Default.Chat, "Messages") },
        BottomNavItem(Screen.More, "More") { Icon(Icons.Default.MoreHoriz, "More") },
    )

    // §1.5 — §22.2 Adaptive Navigation Suite.
    // NavigationSuiteScaffold auto-picks the correct nav component from the
    // WindowAdaptiveInfo reported by the platform:
    //   compact  width < 600dp  → NavigationBar  (bottom, thumb reach)
    //   medium   600–839dp      → NavigationRail (leading edge, large phone / tablet portrait)
    //   expanded ≥ 840dp        → PermanentNavigationDrawer (foldable large / landscape tablet / ChromeOS)
    //
    // When showBottomNav is false (pre-login, detail screens, full-screen flows)
    // we force NavigationSuiteType.None so the scaffold renders zero chrome,
    // delegating layout entirely to the outer Scaffold.
    //
    // CROSS18 outer Scaffold retained for statusBar inset ownership and banners.
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

            // §1 L166 — network-offline banner driven by NetworkMonitor (raw connectivity).
            // Complements the ServerReachabilityMonitor-driven OfflineBanner above:
            // this one fires when there is literally no network interface (e.g. Airplane
            // mode), while the existing one fires when the server is unreachable over an
            // available link. The Retry button triggers an immediate WorkManager sync.
            if (authPreferences?.isLoggedIn == true && networkMonitor != null) {
                val isOnline by networkMonitor.isOnline.collectAsState(initial = true)
                val retryContext: Context = LocalContext.current
                OfflineBanner(
                    isOffline = !isOnline,
                    onRetry = { com.bizarreelectronics.crm.data.sync.SyncWorker.syncNow(retryContext) },
                )
            }

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
                onNewTicket = { navController.navigate(Screen.CheckInEntry.route) },
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
                // §54 — Ctrl+K opens the command palette overlay.
                onCommandPalette = { showCommandPalette = true },
            ) {

            // §1.5 — Adaptive navigation: NavigationSuiteScaffold wraps the
            // NavHost and auto-selects NavigationBar / NavigationRail /
            // PermanentNavigationDrawer from currentWindowAdaptiveInfo().
            // When the nav chrome should be hidden (pre-login, detail views,
            // full-screen flows), layoutType is forced to None so no chrome
            // is rendered. The outer Scaffold still owns the insets.
            val adaptiveInfo = currentWindowAdaptiveInfo()
            val navSuiteType = if (showBottomNav) {
                NavigationSuiteScaffoldDefaults.calculateFromAdaptiveInfo(adaptiveInfo)
            } else {
                NavigationSuiteType.None
            }

            NavigationSuiteScaffold(
                layoutType = navSuiteType,
                navigationSuiteItems = {
                    bottomNavItems.forEach { item ->
                        val isMoreTab = item.screen == Screen.More
                        val isSelected = if (isMoreTab) {
                            currentRoute == Screen.More.route || currentRoute in moreChildRoutes
                        } else {
                            currentRoute == item.screen.route
                        }
                        item(
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
                                } else if (item.screen == Screen.Pos &&
                                    currentRoute in setOf(
                                        Screen.PosCart.route,
                                        Screen.PosTender.route,
                                        Screen.PosSplitCart.route,
                                        Screen.Scanner.route,
                                    )
                                ) {
                                    // Already deep in POS sub-flow — surface
                                    // the reset/continue prompt instead of
                                    // restoring the cart screen straight back.
                                    showPosResetDialog = true
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
                },
                containerColor = MaterialTheme.colorScheme.surface,
            ) {
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
            @OptIn(ExperimentalSharedTransitionApi::class)
            SharedTransitionLayout(modifier = Modifier.fillMaxSize()) {
            val sharedTransitionScope = this
            NavHost(
                navController = navController,
                startDestination = startDest,
                modifier = Modifier.fillMaxSize(),
                // Foldable §23: horizontal slide transitions make predictive-back
                // system gesture preview meaningful — the back-target screen slides
                // in from the left as the user swipes. Navigation 2.8+ with
                // enableOnBackInvokedCallback="true" in the manifest + the system
                // handling predictive back means these transitions are replayed
                // during the drag automatically. 200ms tween is fast enough to feel
                // snappy on a phone but slow enough to be visible on a large tablet.
                enterTransition = {
                    slideInHorizontally(animationSpec = tween(200)) { it } +
                        fadeIn(animationSpec = tween(200))
                },
                exitTransition = {
                    slideOutHorizontally(animationSpec = tween(200)) { -it / 3 } +
                        fadeOut(animationSpec = tween(200))
                },
                popEnterTransition = {
                    slideInHorizontally(animationSpec = tween(200)) { -it / 3 } +
                        fadeIn(animationSpec = tween(200))
                },
                popExitTransition = {
                    slideOutHorizontally(animationSpec = tween(200)) { it } +
                        fadeOut(animationSpec = tween(200))
                },
            ) {
            // §2.7 L330 — the Login route accepts an optional `setupToken` query arg
            // delivered by DeepLinkBus when an invite link is tapped. The arg is
            // nullable/defaultValue=null so existing callers that navigate to
            // Screen.Login.route (no query string) continue to work unchanged.
            composable(
                route = "login?setupToken={setupToken}",
                arguments = listOf(
                    navArgument("setupToken") {
                        type = NavType.StringType
                        nullable = true
                        defaultValue = null
                    },
                ),
            ) { entry ->
                // §28.6 — pick up the reason set by the authCleared observer
                // so the LoginScreen can show "you've been signed out" copy.
                val sessionRevokedReason by entry.savedStateHandle
                    .getStateFlow<String?>("session_revoked_reason", null)
                    .collectAsState()
                val setupToken = entry.arguments?.getString("setupToken")
                LoginScreen(
                    onLoginSuccess = {
                        navController.navigate(Screen.Dashboard.route) {
                            popUpTo("login?setupToken={setupToken}") { inclusive = true }
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
                    // §2.7 L330 — forward invite token from deep link (null on normal start)
                    setupToken = setupToken,
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
                        // §2.10 [plan:L343] — route to the 13-step setup wizard.
                        navController.navigate(Screen.Setup.route) {
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
            // §2.10 [plan:L343] — 13-step first-run tenant onboarding wizard.
            // Deep link: bizarrecrm://setup (invite token handled upstream).
            composable(
                route = Screen.Setup.route,
                deepLinks = listOf(
                    navDeepLink { uriPattern = "bizarrecrm://setup" },
                ),
            ) {
                SetupWizardScreen(
                    onSetupComplete = {
                        navController.navigate(Screen.Dashboard.route) {
                            popUpTo(0) { inclusive = true }
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
            // §2.15 L387-L388 — Forgot-PIN self-service reset.
            // Pre-auth: reachable from the PIN lock screen "Forgot PIN?" button.
            // On success, pop back to wherever the user came from (lock screen
            // clears and resumes normally once the new PIN is set locally).
            composable(Screen.ForgotPin.route) {
                ForgotPinScreen(
                    onBack = { navController.popBackStack() },
                    onSuccess = { navController.popBackStack() },
                )
            }
            composable(Screen.Dashboard.route) {
                DashboardScreen(
                    onNavigateToTicket = { id -> navController.navigate(Screen.TicketDetail.createRoute(id)) },
                    onNavigateToTickets = { navController.navigate(Screen.Tickets.route) },
                    onCreateTicket = { navController.navigate(Screen.CheckInEntry.route) },
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
                    // §3.16 L593 — "Show more" on the Activity Feed card routes to the full screen.
                    onNavigateToActivityFeed = { navController.navigate(Screen.ActivityFeed.route) },
                    // §3.2 L504 — Cash-Trapped card tap → Aging report.
                    onNavigateToAging = { navController.navigate(Screen.InvoicesAging.route) },
                )
            }
            // §3.16 L592-L599 — Full-screen Activity Feed.
            composable(Screen.ActivityFeed.route) {
                ActivityFeedScreen(
                    onBack = { navController.popBackStack() },
                    onNavigate = { route -> navController.navigate(route) },
                )
            }
            composable(Screen.Tickets.route) {
                @OptIn(ExperimentalSharedTransitionApi::class)
                TicketListScreen(
                    sharedTransitionScope = sharedTransitionScope,
                    animatedContentScope = this@composable,
                    onTicketClick = { id -> navController.navigate(Screen.TicketDetail.createRoute(id)) },
                    onCreateClick = { navController.navigate(Screen.CheckInEntry.route) },
                )
            }
            composable(Screen.TicketDetail.route) { backStackEntry ->
                val ticketId = backStackEntry.arguments?.getString("id")?.toLongOrNull() ?: return@composable
                @OptIn(ExperimentalSharedTransitionApi::class)
                TicketDetailScreen(
                    sharedTransitionScope = sharedTransitionScope,
                    animatedContentScope = this@composable,
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
                    // POS-AUDIT-041: Screen.Checkout (stub) deleted; onCheckout omitted
                    // so the top-bar Checkout icon auto-hides (null guard in TicketDetailScreen).
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
            // Legacy Screen.TicketCreate composable removed 2026-04-24.
            // All callers (POS tile, dashboard "+", tickets-tab FAB, Ctrl+T,
            // CustomerDetail onCreateTicket, deep-link `ticket/new`, estimate
            // promote) now route to Screen.CheckInEntry. The new flow supports
            // optional `?customerId={id}` pre-fill for the customer-detail path.
            composable(Screen.Customers.route) {
                @OptIn(ExperimentalSharedTransitionApi::class)
                CustomerListScreen(
                    sharedTransitionScope = sharedTransitionScope,
                    animatedContentScope = this@composable,
                    onCustomerClick = { id -> navController.navigate(Screen.CustomerDetail.createRoute(id)) },
                    onCreateClick = { navController.navigate(Screen.CustomerCreate.route) },
                )
            }
            // 5.8.2: tag-filtered customer list launched from a TagChip tap.
            composable(
                route = Screen.CustomersFilteredByTag.route,
                arguments = listOf(navArgument("tag") {
                    type = NavType.StringType
                    defaultValue = ""
                }),
            ) { backStackEntry ->
                val tag = backStackEntry.arguments?.getString("tag").orEmpty()
                @OptIn(ExperimentalSharedTransitionApi::class)
                CustomerListScreen(
                    sharedTransitionScope = sharedTransitionScope,
                    animatedContentScope = this@composable,
                    initialTagFilter = tag,
                    onCustomerClick = { id -> navController.navigate(Screen.CustomerDetail.createRoute(id)) },
                    onCreateClick = { navController.navigate(Screen.CustomerCreate.route) },
                )
            }
            composable(Screen.CustomerDetail.route) { backStackEntry ->
                val customerId = backStackEntry.arguments?.getString("id")?.toLongOrNull() ?: return@composable
                @OptIn(ExperimentalSharedTransitionApi::class)
                CustomerDetailScreen(
                    sharedTransitionScope = sharedTransitionScope,
                    animatedContentScope = this@composable,
                    customerId = customerId,
                    onBack = { navController.popBackStack() },
                    onNavigateToTicket = { id -> navController.navigate(Screen.TicketDetail.createRoute(id)) },
                    onNavigateToSms = { phone -> navController.navigate(Screen.SmsThread.createRoute(phone)) },
                    // CROSS47 + CROSS47-seed: pass the customer id so the
                    // wizard pre-selects the customer and opens on the
                    // Category step instead of forcing a second customer
                    // picker trip.
                    onCreateTicket = { id -> navController.navigate(Screen.CheckInEntry.createRoute(id)) },
                    // 5.8.2: tag chip tap → tag-filtered customer list
                    onNavigateToTagFilter = { tag ->
                        navController.navigate(Screen.CustomersFilteredByTag.createRoute(tag))
                    },
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
            // Phase 2: POS entry → cart → tender → receipt sub-flow
            composable(Screen.Pos.route) {
                PosEntryScreen(
                    onNavigateToCart = { navController.navigate(Screen.PosCart.route) },
                    onNavigateToCheckin = { customerId ->
                        // customerId can be null (no attach), 0L (walk-in), or >0
                        // (real customer). Pass through verbatim so CheckInEntry's
                        // preFillCustomer can switch on the sentinel.
                        navController.navigate(
                            if (customerId != null) Screen.CheckInEntry.createRoute(customerId)
                            else Screen.CheckInEntry.route
                        )
                    },
                    onNavigateToTender = { navController.navigate(Screen.PosTender.route) },
                    onNavigateToTicket = { id -> navController.navigate(Screen.TicketDetail.createRoute(id)) },
                    // AUDIT-030: wire dedicated store-credit payment screen.
                    onNavigateToStoreCreditPayment = { navController.navigate(Screen.StoreCreditPayment.route) },
                )
            }
            // AUDIT-030: store-credit payment path tile destination (placeholder).
            composable(Screen.StoreCreditPayment.route) {
                StoreCreditPaymentScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.PosCart.route) { backStack ->
                // Scanner screen hands the result back via this entry's
                // savedStateHandle["scanned_barcode"]. Expose it as a Flow
                // the cart screen consumes + clears after adding to cart.
                val scannedFlow = backStack.savedStateHandle
                    .getStateFlow<String?>("scanned_barcode", null)
                PosCartScreen(
                    onNavigateToTender = { navController.navigate(Screen.PosTender.route) },
                    onBack = { navController.popBackStack() },
                    onScanBarcode = { navController.navigate(Screen.Scanner.route) },
                    onSplitCart = { navController.navigate(Screen.PosSplitCart.route) },
                    scannedBarcodeFlow = scannedFlow,
                    onScannedBarcodeConsumed = {
                        backStack.savedStateHandle["scanned_barcode"] = null
                    },
                    // TASK-3: pass authPreferences so CartLineBottomSheet can gate price editing
                    authPreferences = authPreferences,
                )
            }
            composable(Screen.PosTender.route) {
                PosTenderScreen(
                    onNavigateToReceipt = { orderId ->
                        navController.navigate(Screen.PosReceipt.createRoute(orderId)) {
                            popUpTo(Screen.Pos.route)
                        }
                    },
                    onBack = { navController.popBackStack() },
                )
            }
            // TASK-6: split cart stub
            composable(Screen.PosSplitCart.route) {
                PosSplitCartScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(
                route = Screen.PosReceipt.route,
                arguments = listOf(navArgument("orderId") { type = NavType.StringType }),
            ) {
                PosReceiptScreen(
                    onOpenTicket = { ticketId -> navController.navigate(Screen.TicketDetail.createRoute(ticketId)) },
                    onNewSale = {
                        navController.navigate(Screen.Pos.route) {
                            popUpTo(Screen.Pos.route) { inclusive = true }
                        }
                    },
                )
            }
            // Phase 3: 6-step repair check-in package (Symptoms → Details →
            // Damage → Diagnostic → Quote → Sign). Requires customer + device
            // attached at nav time; nav args carry both the IDs and display
            // names so CheckInHostScreen can render the header without an
            // extra round-trip.
            composable(
                route = Screen.CheckIn.route,
                arguments = listOf(
                    navArgument("customerId") { type = NavType.LongType },
                    navArgument("deviceId") { type = NavType.LongType },
                    navArgument("customerName") {
                        type = NavType.StringType
                        nullable = true
                        defaultValue = null
                    },
                    navArgument("deviceName") {
                        type = NavType.StringType
                        nullable = true
                        defaultValue = null
                    },
                ),
            ) { backStack ->
                val customerId = backStack.arguments?.getLong("customerId") ?: 0L
                val deviceId = backStack.arguments?.getLong("deviceId") ?: 0L
                val customerName = backStack.arguments?.getString("customerName").orEmpty()
                val deviceName = backStack.arguments?.getString("deviceName").orEmpty()
                com.bizarreelectronics.crm.ui.screens.checkin.CheckInHostScreen(
                    customerId = customerId,
                    deviceId = deviceId,
                    customerName = customerName,
                    deviceName = deviceName,
                    onBack = { navController.popBackStack() },
                    onTicketCreated = { ticketId ->
                        navController.navigate(Screen.TicketDetail.createRoute(ticketId)) {
                            popUpTo(Screen.Pos.route)
                        }
                    },
                )
            }
            // CheckInEntry: pre-step that gathers customer + device info before
            // launching CheckInHostScreen with the required nav args.
            composable(
                route = Screen.CheckInEntry.route,
                arguments = listOf(
                    navArgument("customerId") {
                        type = NavType.LongType
                        defaultValue = -1L
                    },
                ),
            ) { backStack ->
                val preFillCustomerId = backStack.arguments?.getLong("customerId") ?: -1L
                com.bizarreelectronics.crm.ui.screens.checkin.entry.CheckInEntryScreen(
                    preFillCustomerId = preFillCustomerId,
                    onCancel = { navController.popBackStack() },
                    onStartCheckIn = { customerId, customerName, deviceName ->
                        navController.navigate(
                            Screen.CheckIn.createRoute(customerId, 0L, customerName, deviceName)
                        ) { popUpTo(Screen.CheckInEntry.route) { inclusive = true } }
                    },
                )
            }
            // POS-AUDIT-041: Screen.Checkout + Screen.TicketSuccess composables removed.
            // Both were Phase-3 stubs ("Coming soon" / placeholder text only).
            // The new check-in flow (CheckInEntry → CheckIn) handles ticket creation;
            // CheckoutScreen.kt and TicketSuccessScreen.kt have been deleted.
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
                    onAgingClick = { navController.navigate(Screen.InvoicesAging.route) },
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
            composable(Screen.InvoicesAging.route) {
                InvoiceAgingScreen(
                    onBack = { navController.popBackStack() },
                    onInvoiceClick = { id -> navController.navigate(Screen.InvoiceDetail.createRoute(id)) },
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
                ReportsScreen(navController = navController)
            }
            // §15 L1722 — sub-report routes (deep-link targets from SegmentedButton)
            composable(Screen.ReportSales.route) {
                com.bizarreelectronics.crm.ui.screens.reports.SalesReportScreen(
                    onDrillThroughDate = { date -> navController.navigate("tickets?date=$date") },
                    onReprintOrder = { orderId ->
                        navController.navigate(Screen.PosReceipt.createRoute(orderId))
                    },
                )
            }
            composable(Screen.ReportTickets.route) {
                com.bizarreelectronics.crm.ui.screens.reports.TicketsReportScreen()
            }
            composable(Screen.ReportInventory.route) {
                com.bizarreelectronics.crm.ui.screens.reports.InventoryReportScreen()
            }
            composable(Screen.ReportTax.route) {
                com.bizarreelectronics.crm.ui.screens.reports.TaxReportScreen()
            }
            composable(
                route = Screen.ReportCustom.route,
                deepLinks = listOf(
                    // §15.8 — custom-scheme deep-link: bizarrecrm://reports/custom/<id>
                    // Allows sharing a saved custom report via shareCustomReport() in CustomReportScreen.
                    navDeepLink { uriPattern = "bizarrecrm://reports/custom/{id}" },
                ),
            ) {
                com.bizarreelectronics.crm.ui.screens.reports.CustomReportScreen()
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
            // §14.6 — Team shifts weekly schedule
            composable(Screen.ShiftsSchedule.route) {
                com.bizarreelectronics.crm.ui.screens.shifts.ShiftsScheduleScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            // §14.7 — Employee leaderboard
            composable(Screen.Leaderboard.route) {
                com.bizarreelectronics.crm.ui.screens.employees.LeaderboardScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            // §14.4 — Role management (admin)
            composable(Screen.RoleManagement.route) {
                com.bizarreelectronics.crm.ui.screens.employees.RoleManagementScreen(
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
                    // §2.14 [plan:L369-L378] — Shared Device Mode sub-screen.
                    // Gate: admin role only. Non-admin sessions fall through to SwitchUser
                    // for PIN verification before landing on SharedDevice.
                    onSharedDevice = { navController.navigate(Screen.SharedDevice.route) },
                    // §1.3 [plan:L185] — Diagnostics → Export DB snapshot. DEBUG only.
                    onDiagnostics = { navController.navigate(Screen.Diagnostics.route) },
                    // §1.2 [plan:L258] — Rate-limit bucket state viewer. DEBUG only.
                    onRateLimitBuckets = { navController.navigate(Screen.RateLimitBuckets.route) },
                    // §3.13 L565–L567 — Display sub-screen (TV queue board + keep-screen-on).
                    onDisplay = { navController.navigate(Screen.DisplaySettings.route) },
                    // §3.19 L613–L616 — Appearance / dashboard density picker.
                    onAppearance = { navController.navigate(Screen.Appearance.route) },
                    // §17.4/17.5 — Hardware sub-screen (printers + BlockChyp terminal).
                    onHardware = { navController.navigate(Screen.HardwareSettings.route) },
                    // §38 — Memberships / Loyalty.
                    onMemberships = { navController.navigate(Screen.Memberships.route) },
                    // §39 — Cash Register / Z-Report.
                    onCashRegister = { navController.navigate(Screen.CashRegister.route) },
                    // §40 — Gift Cards / Store Credit.
                    onGiftCards = { navController.navigate(Screen.GiftCards.route) },
                    // §19.7 — Ticket settings.
                    onTicketSettings = { navController.navigate(Screen.TicketSettings.route) },
                    // §19.8 — POS / payment settings.
                    onPosSettings = { navController.navigate(Screen.PosSettings.route) },
                    // §19.9 — SMS settings.
                    onSmsSettings = { navController.navigate(Screen.SmsSettings.route) },
                    // §19.19 — Business info.
                    onBusinessInfo = { navController.navigate(Screen.BusinessInfo.route) },
                    // §44.1 — Device templates.
                    onDeviceTemplates = { navController.navigate(Screen.DeviceTemplates.route) },
                    // §44.2 — Repair pricing catalog.
                    onRepairPricing = { navController.navigate(Screen.RepairPricing.route) },
                    // §44.3 — Device catalog.
                    onDeviceCatalog = { navController.navigate(Screen.DeviceCatalog.route) },
                )
            }
            // §19.7 — Ticket settings sub-screen.
            composable(Screen.TicketSettings.route) {
                TicketSettingsScreen(onBack = { navController.popBackStack() })
            }
            // §19.8 — POS / payment settings sub-screen.
            composable(Screen.PosSettings.route) {
                PosSettingsScreen(onBack = { navController.popBackStack() })
            }
            // §19.9 — SMS settings sub-screen.
            composable(Screen.SmsSettings.route) {
                SmsSettingsScreen(onBack = { navController.popBackStack() })
            }
            // §19.19 — Business info sub-screen.
            composable(Screen.BusinessInfo.route) {
                BusinessInfoScreen(onBack = { navController.popBackStack() })
            }
            // §3.13 L565–L567 — Display settings sub-screen.
            composable(Screen.DisplaySettings.route) {
                DisplaySettingsScreen(
                    onBack = { navController.popBackStack() },
                    // Navigate to TV queue board; board calls onExitRequest → PIN → popBackStack.
                    onActivateBoard = { navController.navigate(Screen.TvQueueBoard.route) },
                )
            }
            // §3.19 L613–L616 — Appearance / dashboard density picker.
            composable(Screen.Appearance.route) {
                AppearanceScreen(onBack = { navController.popBackStack() })
            }
            // §3.13 L565–L567 — Full-screen TV queue board.
            // Exit: 3-finger tap → navigate to PinLockScreen with onUnlocked → popBackStack().
            // ChromeOS Escape key is handled at the activity level and maps to popBackStack(),
            // which lands on PinLockScreen as the next item in the back stack here.
            composable(Screen.TvQueueBoard.route) {
                TvQueueBoardScreen(
                    onExitRequest = {
                        // Navigate to the PIN lock screen. On successful PIN entry the
                        // PinLockScreen calls onUnlocked, which the caller here wires to
                        // popBackStack() → returns to Dashboard (the screen beneath the board).
                        // We use a nested route so the PIN screen covers the board without
                        // leaving the board in the back stack after unlock.
                        navController.navigate(Screen.PinSetup.route) {
                            // Keep the board in the back stack so Cancel on PIN returns to it.
                            launchSingleTop = true
                        }
                    },
                )
            }
            // §36 L585–L588 — Morning-open checklist (staff role, shown once per day).
            composable(Screen.MorningChecklist.route) {
                com.bizarreelectronics.crm.ui.screens.morning.MorningChecklistScreen(
                    onBack = { navController.popBackStack() },
                    onNavigateToRoute = { route -> navController.navigate(route) },
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
            // §1.2 [plan:L258] — Rate-limit bucket state viewer. DEBUG builds only;
            // SettingsScreen never navigates here in release builds.
            composable(Screen.RateLimitBuckets.route) {
                RateLimitBucketsScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.About.route) {
                com.bizarreelectronics.crm.ui.screens.settings.AboutScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            // §37 — Marketing & Growth
            composable(Screen.Marketing.route) {
                com.bizarreelectronics.crm.ui.screens.marketing.MarketingScreen(
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
                    // §2.11: Active sessions screen wired (ActionPlan L350).
                    onActiveSessions = { navController.navigate(Screen.ActiveSessions.route) },
                    // §2.19: Recovery codes screen wired (ActionPlan L427-L438).
                    onRecoveryCodes = { navController.navigate(Screen.RecoveryCodes.route) },
                    // §2.18 L421: Manage 2FA factors (Owner/Manager/Admin).
                    // Role check is deferred — shown for all authenticated users for now.
                    // Document: role-gate wiring tracked as follow-up when Session role
                    // is accessible from the nav composable scope.
                    onManageTwoFactorFactors = { navController.navigate(Screen.TwoFactorFactors.route) },
                    // §2.22 L463: Passkeys screen — shown for all authenticated users.
                    // PasskeyScreen guards API < 28 internally.
                    onPasskeys = { navController.navigate(Screen.Passkeys.route) },
                )
            }
            // §2.22 L463 — Passkey management screen (enroll, list, remove).
            composable(Screen.Passkeys.route) {
                PasskeyScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            // §2.11 — Active sessions list + revoke.
            composable(Screen.ActiveSessions.route) {
                ActiveSessionsScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            // §2.9 — Change-password screen (authenticated, under Security).
            composable(Screen.ChangePassword.route) {
                ChangePasswordScreen(
                    onBack = { navController.popBackStack() },
                    onPasswordChanged = { navController.popBackStack() },
                )
            }
            // §2.19 — Recovery codes screen (ActionPlan L427-L438).
            // Generate new one-time recovery codes with password re-auth.
            composable(Screen.RecoveryCodes.route) {
                RecoveryCodesScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            // §2.18 L421 — Manage 2FA factors screen (ActionPlan L417-L426).
            // TOTP enroll navigates to existing 2FA setup step; SMS prompts phone;
            // passkey + hardware_key show coming-soon bottom-sheet stubs.
            composable(Screen.TwoFactorFactors.route) {
                TwoFactorFactorsScreen(
                    onBack = { navController.popBackStack() },
                    // Reuse existing TOTP enroll step (commit cd36e98 QR path).
                    // Navigate back to the 2fa-setup route which is already wired
                    // in the login/auth flow. popBackStack keeps the security back-stack clean.
                    onNavigateToTotpEnroll = { navController.popBackStack() },
                )
            }
            // plan:L2009-L2014 — Security Summary consolidated view.
            // Deep link: bizarrecrm://settings/security-summary
            composable(
                route = Screen.SecuritySummary.route,
                deepLinks = listOf(
                    navDeepLink { uriPattern = "bizarrecrm://settings/security-summary" },
                ),
            ) {
                SecuritySummaryScreen(
                    onBack = { navController.popBackStack() },
                    onNavigate = { route -> navController.navigate(route) },
                )
            }
            // plan:L1976/L1978 — deep links for individual settings entries.
            // Pattern: bizarrecrm://settings/<id> → resolves via SettingsMetadata.findById
            // and navigates to the entry's route. Handled by the generic deep-link
            // composable below (route must be in the nav graph already).
            // Note: individual entry routes (profile, notifications, appearance, language,
            // security, display, hardware, shared-device, theme) are already declared above.

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
            // §2.14 [plan:L369-L378] — Shared-Device Mode settings sub-screen.
            // Gated by manager role: the SettingsScreen row navigates here only
            // when the current session has role == "admin". Non-admin users see
            // the row but tapping it shows the SwitchUserScreen PIN dialog first.
            composable(Screen.SharedDevice.route) {
                SharedDeviceScreen(
                    onBack = { navController.popBackStack() },
                )
            }
            // §2.14 [plan:L369-L378] — Staff picker (kiosk lock screen).
            // Entered automatically by the inactivity observer (AppNavGraph LaunchedEffect
            // or MainActivity) when sharedDeviceModeEnabled=true and idle > threshold.
            // Back stack is always cleared to prevent navigating back to protected content.
            composable(Screen.StaffPicker.route) {
                StaffPickerScreen(
                    onStaffSelected = { username ->
                        // Navigate to SwitchUserScreen pre-scoped to the selected username.
                        // SwitchUserScreen handles POST /auth/switch-user and on success
                        // routes to Dashboard clearing the back stack.
                        navController.navigate(Screen.SwitchUser.route) {
                            // Keep StaffPicker beneath SwitchUser so Back returns to it
                            // (staff can cancel and pick a different avatar).
                            launchSingleTop = true
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
                    onResult = { type, id, secondaryKey ->
                        when (type) {
                            "ticket"      -> navController.navigate(Screen.TicketDetail.createRoute(id))
                            "customer"    -> navController.navigate(Screen.CustomerDetail.createRoute(id))
                            "invoice"     -> navController.navigate(Screen.InvoiceDetail.createRoute(id))
                            "inventory"   -> navController.navigate(Screen.InventoryDetail.createRoute(id))
                            "employee"    -> navController.navigate(Screen.EmployeeDetail.createRoute(id))
                            "lead"        -> navController.navigate(Screen.LeadDetail.createRoute(id))
                            // Appointment — no detail route yet; land on list
                            "appointment" -> navController.navigate(Screen.Appointments.route)
                            // SMS thread — keyed by phone number, not numeric id
                            "sms"         -> {
                                val phone = secondaryKey
                                if (!phone.isNullOrBlank()) {
                                    navController.navigate(Screen.SmsThread.createRoute(phone))
                                } else {
                                    navController.navigate(Screen.Messages.route)
                                }
                            }
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
                    // 8.3 — "Convert to estimate" navigates to the new estimate detail if
                    // the server created one, or to EstimateCreate with lead prefill as
                    // a fallback (404 path).
                    onConvertedToEstimate = { estimateId ->
                        navController.navigate(Screen.EstimateDetail.createRoute(estimateId)) {
                            popUpTo(Screen.Leads.route)
                        }
                    },
                    onNavigateToEstimateCreate = { id ->
                        navController.navigate(Screen.EstimateCreate.createRoute(leadId = id))
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
                    onAppointmentClick = { id ->
                        navController.navigate(Screen.AppointmentDetail.createRoute(id))
                    },
                )
            }
            composable(Screen.AppointmentCreate.route) {
                com.bizarreelectronics.crm.ui.screens.leads.AppointmentCreateScreen(
                    onBack = { navController.popBackStack() },
                    onCreated = { _ -> navController.popBackStack() },
                )
            }
            composable(
                route = Screen.AppointmentDetail.route,
                arguments = listOf(navArgument("appointmentId") { type = NavType.LongType }),
            ) {
                com.bizarreelectronics.crm.ui.screens.appointments.AppointmentDetailScreen(
                    onBack = { navController.popBackStack() },
                    onNavigateToCustomer = { id ->
                        navController.navigate(Screen.CustomerDetail.createRoute(id))
                    },
                    onNavigateToTicket = { id ->
                        navController.navigate(Screen.TicketDetail.createRoute(id))
                    },
                    onNavigateToEstimate = { id ->
                        navController.navigate(Screen.EstimateDetail.createRoute(id))
                    },
                    // TODO(10.2): wire onNavigateToLead once LeadDetail route accepts a Long
                    onNavigateToLead = null,
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
                    onCreateClick = { navController.navigate(Screen.EstimateCreate.createRoute()) },
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
            composable(
                route = Screen.EstimateCreate.route,
                arguments = listOf(
                    navArgument("leadId") {
                        type = NavType.StringType
                        nullable = true
                        defaultValue = null
                    },
                ),
            ) {
                com.bizarreelectronics.crm.ui.screens.estimates.EstimateCreateScreen(
                    onBack = { navController.popBackStack() },
                    onCreated = { id ->
                        navController.navigate(Screen.EstimateDetail.createRoute(id)) {
                            popUpTo(Screen.Estimates.route)
                        }
                    },
                )
            }

            // ─── Expenses ───
            composable(Screen.Expenses.route) {
                com.bizarreelectronics.crm.ui.screens.expenses.ExpenseListScreen(
                    onCreateClick = { navController.navigate(Screen.ExpenseCreate.route) },
                    onDetailClick = { id -> navController.navigate(Screen.ExpenseDetail.createRoute(id)) },
                )
            }
            composable(Screen.ExpenseCreate.route) {
                com.bizarreelectronics.crm.ui.screens.expenses.ExpenseCreateScreen(
                    onBack = { navController.popBackStack() },
                    onCreated = { navController.popBackStack() },
                )
            }
            composable(
                route = Screen.ExpenseDetail.route,
                arguments = listOf(navArgument("id") { type = NavType.LongType }),
            ) {
                com.bizarreelectronics.crm.ui.screens.expenses.ExpenseDetailScreen(
                    onBack = { navController.popBackStack() },
                    onEdit = { id ->
                        // Navigate to create in edit mode — edit mode not yet wired,
                        // popBackStack to list as fallback until edit-mode route exists.
                        navController.popBackStack()
                    },
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

            // ─── §17.1-§17.5 Hardware routes ───

            // §17.1 — CameraX capture screen. Route carries ticketId + deviceId so photos
            // are uploaded to the correct ticket and device_id multipart field.
            composable(
                route = Screen.CameraCapture.route,
                arguments = listOf(
                    navArgument("ticketId") { type = NavType.LongType },
                    navArgument("deviceId") { type = NavType.LongType },
                ),
            ) { backStackEntry ->
                val ticketId = backStackEntry.arguments?.getLong("ticketId") ?: 0L
                val deviceId = backStackEntry.arguments?.getLong("deviceId") ?: 0L
                CameraCaptureScreen(
                    ticketId = ticketId,
                    deviceId = deviceId,
                    onBack = { navController.popBackStack() },
                )
            }

            // §17.3 — Document scanning screen.
            composable(Screen.DocumentScan.route) {
                DocumentScanScreen(
                    onBack = { navController.popBackStack() },
                    onDocumentScanned = { _ ->
                        // URI handled inside the screen (WorkManager upload).
                        navController.popBackStack()
                    },
                )
            }

            // §17.4/17.5 — Hardware settings hub: printers + BlockChyp terminal.
            composable(Screen.HardwareSettings.route) {
                HardwareSettingsScreen(
                    onBack = { navController.popBackStack() },
                    onNavigateToPrinters = { navController.navigate(Screen.PrinterDiscovery.route) },
                )
            }

            // §17.4 — Printer discovery & pairing sub-screen.
            composable(Screen.PrinterDiscovery.route) {
                PrinterDiscoveryScreen(
                    onBack = { navController.popBackStack() },
                )
            }

            // ─── §4.9 L756 — Bench Tab ───
            composable(Screen.Bench.route) {
                BenchTabScreen(
                    onBack = { navController.popBackStack() },
                    onNavigateToTicket = { id -> navController.navigate(Screen.TicketDetail.createRoute(id)) },
                    onNavigateToTemplates = { navController.navigate(Screen.DeviceTemplates.route) },
                )
            }

            // ─── §4.9 L762 — Device Templates ───
            composable(Screen.DeviceTemplates.route) {
                DeviceTemplatesScreen(
                    onBack = { navController.popBackStack() },
                )
            }

            // ─── §4.9 L766 — Repair Pricing ───
            composable(Screen.RepairPricing.route) {
                RepairPricingScreen(
                    onBack = { navController.popBackStack() },
                )
            }

            // ─── §44.3 — Device Catalog ───
            composable(Screen.DeviceCatalog.route) {
                DeviceCatalogScreen(
                    onBack = { navController.popBackStack() },
                    isAdmin = authPreferences?.userRole == "admin",
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

            // ─── §41 Payment Links ───
            composable(Screen.PaymentLinks.route) {
                com.bizarreelectronics.crm.ui.screens.payments.PaymentLinkListScreen(
                    onCreateClick = { navController.navigate(Screen.PaymentLinkCreate.route) },
                )
            }
            composable(Screen.PaymentLinkCreate.route) {
                com.bizarreelectronics.crm.ui.screens.payments.PaymentLinkScreen(
                    onBack = { navController.popBackStack() },
                    onCreated = { navController.popBackStack() },
                )
            }

            // ─── §42 Calls ───
            composable(Screen.Calls.route) {
                com.bizarreelectronics.crm.ui.screens.calls.CallsTabScreen(
                    onCallClick = { id -> navController.navigate(Screen.CallDetail.createRoute(id)) },
                    // Outbound call initiation — number-picker pre-step TBD
                    onInitiateCall = { navController.navigate(Screen.Calls.route) },
                )
            }
            composable(
                route = Screen.CallDetail.route,
                arguments = listOf(navArgument("id") { type = NavType.LongType }),
            ) {
                com.bizarreelectronics.crm.ui.screens.calls.CallDetailScreen(
                    callId = it.arguments?.getLong("id") ?: return@composable,
                    onBack = { navController.popBackStack() },
                )
            }

            // ─── §38 Memberships / Loyalty ───────────────────────────────────
            composable(Screen.Memberships.route) {
                MembershipListScreen(
                    onBack = { navController.popBackStack() },
                    onNavigateToCustomer = { id ->
                        navController.navigate(Screen.CustomerDetail.createRoute(id))
                    },
                )
            }

            // ─── §39 Cash Register / Z-Report ────────────────────────────────
            composable(Screen.CashRegister.route) {
                CashRegisterScreen(
                    onBack = { navController.popBackStack() },
                )
            }

            // ─── §40 Gift Cards / Store Credit ───────────────────────────────
            composable(Screen.GiftCards.route) {
                GiftCardScreen(
                    onBack = { navController.popBackStack() },
                )
            }

            // ─── §47 Team Chat ────────────────────────────────────────────────
            composable(Screen.TeamChat.route) {
                com.bizarreelectronics.crm.ui.screens.team.TeamChatListScreen(
                    onRoomClick = { roomId, roomName ->
                        navController.navigate(Screen.TeamChatThread.createRoute(roomId, roomName))
                    },
                )
            }
            composable(
                route = Screen.TeamChatThread.route + "?roomName={roomName}",
                arguments = listOf(
                    navArgument("roomId") { type = NavType.StringType },
                    navArgument("roomName") {
                        type = NavType.StringType
                        defaultValue = ""
                    },
                ),
            ) {
                com.bizarreelectronics.crm.ui.screens.team.TeamChatThreadScreen(
                    onBack = { navController.popBackStack() },
                )
            }

            // ─── §48 Goals ────────────────────────────────────────────────────
            composable(Screen.Goals.route) {
                com.bizarreelectronics.crm.ui.screens.goals.GoalsScreen(
                    onBack = { navController.popBackStack() },
                )
            }

            // ─── §48 Performance Reviews ──────────────────────────────────────
            composable(Screen.PerformanceReviews.route) {
                com.bizarreelectronics.crm.ui.screens.performance.PerformanceReviewScreen(
                    onBack = { navController.popBackStack() },
                )
            }

            // ─── §48 Time-Off Request (staff) ─────────────────────────────────
            composable(Screen.TimeOffRequest.route) {
                com.bizarreelectronics.crm.ui.screens.timeoff.TimeOffRequestScreen(
                    onBack = { navController.popBackStack() },
                )
            }

            // ─── §48 Time-Off List / Approval Queue (manager) ─────────────────
            composable(Screen.TimeOffList.route) {
                com.bizarreelectronics.crm.ui.screens.timeoff.TimeOffListScreen(
                    onBack = { navController.popBackStack() },
                )
            }

            // ─── §52 Audit Logs (admin-only) ──────────────────────────────────
            // Role gate: AuditLogsScreen itself also renders an access-denied
            // message for defense-in-depth, but callers should prefer to only
            // surface this route in admin-visible navigation (MoreScreen / Settings).
            composable(Screen.AuditLogs.route) {
                val isAdmin = authPreferences?.userRole == "admin"
                AuditLogsScreen(
                    isAdmin = isAdmin,
                    onBack = { navController.popBackStack() },
                )
            }

            // ─── §50 Data Import (admin-only) ─────────────────────────────────
            // Role gate enforced in DataImportViewModel.isAdmin; server also enforces.
            // 404-tolerant: screen shows "not configured" if /imports/* returns 404.
            composable(Screen.DataImport.route) {
                DataImportScreen(
                    onNavigateBack = { navController.popBackStack() },
                )
            }

            // ─── §51 Data Export (manager+) ───────────────────────────────────
            // Role gate enforced in DataExportViewModel.canExport; server enforces too.
            // 404-tolerant: screen shows "not configured" if /exports/* returns 404.
            composable(Screen.DataExport.route) {
                DataExportScreen(
                    onNavigateBack = { navController.popBackStack() },
                )
            }
        }
        } // close SharedTransitionLayout
        } // close NavigationSuiteScaffold content (§1.5)
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

        // §54 — Command palette overlay. Triggered by Ctrl+K (wired above in
        // KeyboardShortcutsHost.onCommandPalette). Only shown when logged in.
        if (showCommandPalette && authPreferences?.isLoggedIn == true) {
            CommandPaletteScreen(
                onNavigate = { route ->
                    showCommandPalette = false
                    navController.navigate(route)
                },
                onDismiss = { showCommandPalette = false },
            )
        }

        if (showPosResetDialog) {
            val session = posCoordinator?.session?.collectAsState()?.value
            val lineCount = session?.lines?.size ?: 0
            val total = session?.totalCents ?: 0L
            val totalLabel = "${'$'}${total / 100}.${(total % 100).toString().padStart(2, '0')}"
            AlertDialog(
                onDismissRequest = { showPosResetDialog = false },
                title = { Text("POS session in progress") },
                text = {
                    Text(
                        if (lineCount == 0) "Cart is empty. Restart with a fresh customer?"
                        else "$lineCount item${if (lineCount == 1) "" else "s"} · $totalLabel in cart. " +
                                "Continue the current sale or start over with a fresh cart?"
                    )
                },
                confirmButton = {
                    TextButton(onClick = {
                        // Start over: clear coordinator session + nav to entry root.
                        posCoordinator?.resetSession()
                        showPosResetDialog = false
                        navController.navigate(Screen.Pos.route) {
                            popUpTo(Screen.Pos.route) { inclusive = true }
                            launchSingleTop = true
                        }
                    }) { Text("Start over") }
                },
                dismissButton = {
                    TextButton(onClick = {
                        // Continue: pop back to PosEntry, keep session intact.
                        showPosResetDialog = false
                        navController.popBackStack(Screen.Pos.route, inclusive = false)
                    }) { Text("Continue") }
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
                MoreItem(Icons.Default.BarChart,        "Reports",       Screen.Reports.route),
                MoreItem(Icons.Default.Group,           "Employees",     Screen.Employees.route),
                // §37 — Marketing & Growth
                MoreItem(Icons.Default.Campaign,        "Marketing",     Screen.Marketing.route),
                // §38 — Memberships / Loyalty
                MoreItem(Icons.Default.CardMembership,  "Memberships",   Screen.Memberships.route),
                // §39 — Cash Register / Z-Report
                MoreItem(Icons.Default.PointOfSale,     "Cash Register", Screen.CashRegister.route),
                // §40 — Gift Cards / Store Credit
                MoreItem(Icons.Default.CardGiftcard,    "Gift Cards",    Screen.GiftCards.route),
                // §47 — Team Chat internal messaging
                MoreItem(Icons.Default.Forum,           "Team Chat",     Screen.TeamChat.route),
                // §14.6 — Team shifts weekly schedule
                MoreItem(Icons.Default.CalendarMonth,   "Schedule",      Screen.ShiftsSchedule.route),
                // §14.7 — Employee leaderboard
                MoreItem(Icons.Default.EmojiEvents,     "Leaderboard",   Screen.Leaderboard.route),
                // §14.4 — Role management (admin)
                MoreItem(Icons.Default.ManageAccounts,  "Roles",         Screen.RoleManagement.route),
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
