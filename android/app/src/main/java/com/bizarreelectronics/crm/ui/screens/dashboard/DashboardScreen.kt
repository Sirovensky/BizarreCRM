package com.bizarreelectronics.crm.ui.screens.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.data.local.db.dao.NotificationDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.repository.DashboardRepository
import com.bizarreelectronics.crm.data.sync.SyncManager
import com.bizarreelectronics.crm.ui.components.DashboardFab
import com.bizarreelectronics.crm.ui.components.SyncStatusBadge
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class KpiCard(
    val label: String,
    val value: String,
    val iconTint: Color,
    /**
     * §3.1 — tile taps deep-link to a filtered list. Null = tile is inert.
     * Used by [KpiCardView] to gate `Modifier.clickable` and give the
     * Card a proper `Role.Button` for TalkBack.
     */
    val onClick: (() -> Unit)? = null,
    val icon: @Composable () -> Unit,
)

data class DashboardUiState(
    val greeting: String = "",
    val openTickets: Int = 0,
    val revenueToday: Double = 0.0,
    val appointmentsToday: Int = 0,
    val lowStockCount: Int = 0,
    val myQueue: List<TicketSummary> = emptyList(),
    val needsAttention: List<AttentionItem> = emptyList(),
    // CROSS1: ticket_all_employees_view_all == '0' enables the assignment feature.
    // When off (default), hide My Queue section entirely.
    val assignmentEnabled: Boolean = false,
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    // U9 fix: per-section error state. The legacy single `error` field merged
    // everything into one generic "some data may be outdated" banner — users
    // had no way to tell which API was down.
    val statsError: String? = null,
    val attentionError: String? = null,
    val queueError: String? = null,
) {
    // True if any of the three parallel loads failed.
    val hasAnyError: Boolean
        get() = statsError != null || attentionError != null || queueError != null
}

data class TicketSummary(val id: Long, val orderId: String, val customerName: String, val statusName: String, val statusColor: String)
data class AttentionItem(val type: String, val message: String, val entityId: Long?)

// U12 fix: hour → greeting is a pure function used by both the VM and any
// Composable that needs to derive a value keyed on the current hour.
internal fun greetingForHour(hour: Int): String = when {
    hour < 12 -> "Good morning"
    hour < 17 -> "Good afternoon"
    else -> "Good evening"
}

@HiltViewModel
class DashboardViewModel @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val dashboardRepository: DashboardRepository,
    private val settingsApi: SettingsApi,
    syncManager: SyncManager,
    syncQueueDao: SyncQueueDao,
    notificationDao: NotificationDao,
) : ViewModel() {

    // Exposed so the Dashboard can render a SyncStatusBadge without the
    // screen layer needing its own Hilt injection. Read-only access to the
    // SyncManager state flow — the screen can tap-to-force-sync via [forceSync].
    val isSyncing: StateFlow<Boolean> = syncManager.isSyncing
    val pendingSyncCount: Flow<Int> = syncQueueDao.getCount()
    // CROSS22-badge: unread-notification count for the dashboard bell badge.
    val unreadNotificationCount: Flow<Int> = notificationDao.getUnreadCount()

    private val syncManagerRef = syncManager

    fun forceSync() {
        viewModelScope.launch {
            try { syncManagerRef.syncAll() } catch (_: Exception) {}
        }
    }


    private val _state = MutableStateFlow(DashboardUiState())
    val state = _state.asStateFlow()

    init {
        loadDashboard()
        collectMyQueue()
        loadAssignmentSetting()
    }

    private fun loadAssignmentSetting() {
        viewModelScope.launch {
            try {
                val cfg = settingsApi.getConfig().data ?: return@launch
                val enabled = cfg["ticket_all_employees_view_all"] == "0"
                _state.value = _state.value.copy(assignmentEnabled = enabled)
            } catch (_: Exception) {
                // Offline / server error — leave at default (off).
            }
        }
    }

    private fun loadDashboard() {
        viewModelScope.launch {
            // CROSS20: fall back to capitalized username when first_name is blank (empty
            // string is truthy in Kotlin ?: chain). Avoids "Good afternoon, admin" lowercase.
            val name = authPreferences.userFirstName?.takeIf { it.isNotBlank() }
                ?: authPreferences.username?.replaceFirstChar { it.uppercase() }
                ?: ""
            // U12 fix: compute the greeting once per load (keyed to "now"),
            // not on every recomposition. greetingForHour is a pure function
            // so we can call it freely.
            val greetingText = greetingForHour(java.time.LocalTime.now().hour)

            _state.value = _state.value.copy(
                greeting = "$greetingText, $name",
                statsError = null,
                attentionError = null,
                queueError = null,
            )

            // U9 fix: track each section's error independently.
            // Stats.
            try {
                val stats = dashboardRepository.getDashboardStats()
                _state.value = _state.value.copy(
                    openTickets = stats.openTickets,
                    revenueToday = stats.revenueToday,
                    appointmentsToday = stats.appointmentsToday,
                    statsError = null,
                )
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "Failed to load stats: ${e.message}")
                _state.value = _state.value.copy(
                    statsError = e.message ?: "Failed to load KPIs",
                )
            }

            // Needs-attention.
            try {
                val attention = dashboardRepository.getNeedsAttention()
                val attentionItems = mutableListOf<AttentionItem>()
                if (attention.staleTicketsCount > 0) attentionItems.add(AttentionItem("ticket", "${attention.staleTicketsCount} stale tickets need attention", null))
                if (attention.missingPartsCount > 0) attentionItems.add(AttentionItem("parts", "${attention.missingPartsCount} parts missing across open tickets", null))
                if (attention.overdueInvoicesCount > 0) attentionItems.add(AttentionItem("invoice", "${attention.overdueInvoicesCount} overdue invoices", null))
                _state.value = _state.value.copy(
                    lowStockCount = attention.lowStockCount,
                    needsAttention = attentionItems,
                    attentionError = null,
                )
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "Failed to load needs-attention: ${e.message}")
                _state.value = _state.value.copy(
                    attentionError = e.message ?: "Failed to load Needs Attention",
                )
            }

            // My Queue refresh.
            try {
                dashboardRepository.refreshMyQueue()
                _state.value = _state.value.copy(queueError = null)
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "Failed to refresh queue: ${e.message}")
                _state.value = _state.value.copy(
                    queueError = e.message ?: "Failed to refresh My Queue",
                )
            }

            _state.value = _state.value.copy(
                isLoading = false,
                isRefreshing = false,
            )
        }
    }

    /** Collect the Room Flow for My Queue — updates automatically when DB changes. */
    private fun collectMyQueue() {
        viewModelScope.launch {
            dashboardRepository.getMyQueue().collect { entities ->
                _state.value = _state.value.copy(
                    myQueue = entities.map { entity ->
                        TicketSummary(
                            id = entity.id,
                            orderId = entity.orderId,
                            customerName = entity.customerName ?: "Unknown",
                            statusName = entity.statusName ?: "",
                            statusColor = entity.statusColor ?: "#6b7280",
                        )
                    },
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadDashboard()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    onNavigateToTicket: (Long) -> Unit,
    onNavigateToTickets: () -> Unit,
    onCreateTicket: () -> Unit = {},
    onCreateCustomer: () -> Unit = {},
    onLogSale: () -> Unit = {},
    onScanBarcode: (() -> Unit)? = null,
    onNavigateToNotifications: (() -> Unit)? = null,
    // §3.11 — opens ClockInOutScreen. Tile rendered above KPI grid; null
    // hides the tile (e.g. previews, non-nav callers).
    onClockInOut: (() -> Unit)? = null,
    // §3.1 — KPI tiles deep-link into the relevant filtered list. Nullable
    // so previews / standalone dashboard tests can pass without a NavController.
    onNavigateToAppointments: (() -> Unit)? = null,
    onNavigateToInventory: (() -> Unit)? = null,
    // §3.9 — tap greeting → Settings → Profile. Nullable keeps previews +
    // isolated tests composable without a NavController.
    onNavigateToProfile: (() -> Unit)? = null,
    // §3.10 — sync badge redirects to Settings → Data → Sync Issues when
    // pending rows are stuck; force-sync stays the default for clean state.
    onNavigateToSyncIssues: (() -> Unit)? = null,
    viewModel: DashboardViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    // [P1] FAB expand state hoisted so this screen can render a scrim overlay.
    // Passed to DashboardFab as expandedState so both share a single source of truth.
    val fabExpandedState = remember { mutableStateOf(false) }

    // Monochrome + state rule: icons muted by default, only tinted when the
    // value conveys state that matters. Zero revenue, zero tickets, zero
    // appointments, zero low-stock = no state, so muted. Once a value is
    // non-zero the icon picks up the semantic hue (primary / success / teal /
    // warning) so a user scanning the grid notices the things that changed.
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val openTicketsTint = if (state.openTickets > 0) MaterialTheme.colorScheme.primary else muted
    val revenueTint = if (state.revenueToday > 0) SuccessGreen else muted
    val apptsTint = if (state.appointmentsToday > 0) MaterialTheme.colorScheme.secondary else muted
    val lowStockTint = if (state.lowStockCount > 0) WarningAmber else muted

    val kpis = listOf(
        KpiCard(
            label = "Open Tickets",
            value = state.openTickets.toString(),
            iconTint = openTicketsTint,
            // §3.1 — tap Open Tickets tile → Tickets list. onNavigateToTickets
            // is required on this screen so always non-null.
            onClick = onNavigateToTickets,
        ) {
            // a11y: decorative — tile is merged; contentDescription on the Card carries the full announcement
            Icon(
                Icons.Default.ConfirmationNumber,
                contentDescription = null,
                tint = openTicketsTint,
            )
        },
        KpiCard(
            label = "Revenue Today",
            value = "$${String.format("%.2f", state.revenueToday)}",
            iconTint = revenueTint,
            // Revenue tile has no detail screen on Android yet — inert tap.
            onClick = null,
        ) {
            // a11y: decorative — tile is merged; contentDescription on the Card carries the full announcement
            Icon(
                Icons.Default.AttachMoney,
                contentDescription = null,
                tint = revenueTint,
            )
        },
        KpiCard(
            label = "Appointments",
            value = state.appointmentsToday.toString(),
            iconTint = apptsTint,
            onClick = onNavigateToAppointments,
        ) {
            // a11y: decorative — tile is merged; contentDescription on the Card carries the full announcement
            Icon(
                Icons.Default.CalendarToday,
                contentDescription = null,
                tint = apptsTint,
            )
        },
        KpiCard(
            label = "Low Stock",
            value = state.lowStockCount.toString(),
            iconTint = lowStockTint,
            onClick = onNavigateToInventory,
        ) {
            // a11y: decorative — tile is merged; contentDescription on the Card carries the full announcement
            Icon(
                Icons.Default.Warning,
                contentDescription = null,
                tint = lowStockTint,
            )
        },
    )

    Scaffold(
        // [P1] BrandTopAppBar hosts the greeting title and sync badge in the
        // action slot, saving a full row in the LazyColumn and anchoring sync
        // status where every Android app puts it.
        //
        // CROSS45: WaveDivider docked directly below the TopAppBar (moved from
        // its previous LazyColumn mid-list position) — canonical placement
        // for every list/dashboard screen.
        topBar = {
            Column {
                BrandTopAppBar(
                    title = state.greeting.ifEmpty { "Dashboard" },
                    // §3.9 — greeting itself is the profile shortcut. When
                    // onNavigateToProfile is wired, render the title as a
                    // clickable Text with role=Button so TalkBack announces
                    // it as an action (the default titleContent is inert).
                    // Null lets BrandTopAppBar fall back to the normal
                    // heading-style Text.
                    titleContent = onNavigateToProfile?.let { onProfile ->
                        {
                            Text(
                                text = state.greeting.ifEmpty { "Dashboard" },
                                style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier
                                    .semantics {
                                        role = Role.Button
                                        heading()
                                    }
                                    .clickable(onClick = onProfile),
                            )
                        }
                    },
                    actions = {
                        // CROSS22 + CROSS22-badge: bell icon + unread count badge.
                        if (onNavigateToNotifications != null) {
                            val unread by viewModel.unreadNotificationCount.collectAsState(initial = 0)
                            BadgedBox(
                                badge = {
                                    if (unread > 0) {
                                        Badge {
                                            Text(if (unread > 99) "99+" else unread.toString())
                                        }
                                    }
                                },
                            ) {
                                IconButton(onClick = onNavigateToNotifications) {
                                    Icon(
                                        Icons.Default.Notifications,
                                        contentDescription = if (unread > 0) "Notifications ($unread unread)" else "Notifications",
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                        SyncStatusBadge(
                            isSyncingFlow = viewModel.isSyncing,
                            pendingCountFlow = viewModel.pendingSyncCount,
                            onForceSync = { viewModel.forceSync() },
                            onOpenIssues = onNavigateToSyncIssues,
                        )
                    },
                )
                WaveDivider()
            }
        },
        floatingActionButton = {
            DashboardFab(
                onNewTicket = onCreateTicket,
                onNewCustomer = onCreateCustomer,
                onLogSale = onLogSale,
                onScanBarcode = onScanBarcode,
                expandedState = fabExpandedState,
            )
        },
    ) { scaffoldPadding ->
    // [P1] Scrim overlay wraps content so it renders above the list
    // but below the Scaffold's FAB layer. The scrim Box is drawn after
    // PullToRefreshBox so it appears on top in Z-order.
    Box(modifier = Modifier.fillMaxSize()) {
    PullToRefreshBox(
        isRefreshing = state.isRefreshing,
        onRefresh = { viewModel.refresh() },
        modifier = Modifier.fillMaxSize().padding(scaffoldPadding),
    ) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // U9 fix: top-of-screen summary banner only appears if ANY section
        // failed, and each failing section also gets its own in-place banner
        // below. This tells users exactly which chunk of the dashboard is
        // stale instead of a generic "some data may be outdated" soup.
        if (state.hasAnyError) {
            item {
                Surface(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = MaterialTheme.shapes.small,
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Default.CloudOff,
                            // decorative — non-clickable banner; sibling "Some sections failed…" Text carries the announcement
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.9f),
                        )
                        Text(
                            "Some sections failed to load. Pull to refresh.",
                            style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp),
                            color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.9f),
                        )
                    }
                }
            }
        }

        // CROSS45: WaveDivider moved to topBar slot (directly below the app bar)
        // so placement is consistent across every list/dashboard screen.

        // §3.5 — getting-started checklist. Auto-hides at 100% complete or
        // when explicitly dismissed; keys off local Room counts + prefs so
        // it works offline.
        item {
            OnboardingChecklist()
        }

        // §3.11 — Clock in/out tile. Surfaces current state pulled from
        // GET /employees and routes to the dedicated screen on tap.
        if (onClockInOut != null) {
            item {
                ClockInTile(onOpen = onClockInOut)
            }
        }

        // [P1] Date sub-line — greeting moved to top bar; only the date remains
        // here as a contextual anchor.
        // CROSS46: route through the canonical DateFormatter.formatAbsolute
        // ("April 16, 2026") instead of the ad-hoc "EEEE, MMMM d" pattern.
        item {
            val todayFormatted = remember {
                com.bizarreelectronics.crm.util.DateFormatter.formatAbsolute(System.currentTimeMillis())
            }
            Text(
                todayFormatted,
                modifier = Modifier.padding(horizontal = 16.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // U9 fix: KPI stats error banner in the KPI section.
        if (state.statsError != null) {
            item {
                SectionErrorBanner(
                    "KPIs failed to load: ${state.statsError}",
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
        }

        // KPI section heading — a11y: heading() so TalkBack announces "Today's KPIs, heading"
        item {
            Text(
                "Today's KPIs",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .semantics { heading() },
            )
        }

        // KPI Cards — 2x2 grid.
        // a11y: liveRegion=Polite on the outer Column so TalkBack announces updated
        // KPI values after a sync completes without interrupting the user.
        item {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { liveRegion = LiveRegionMode.Polite },
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    kpis.take(2).forEach { kpi ->
                        KpiCardView(kpi, modifier = Modifier.weight(1f))
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    kpis.drop(2).forEach { kpi ->
                        KpiCardView(kpi, modifier = Modifier.weight(1f))
                    }
                }
            }
        }

        // CROSS1: entire "My Queue" section hidden when assignment feature is off.
        if (state.assignmentEnabled) {
            // U9 fix: My Queue error banner in-place.
            if (state.queueError != null) {
                item {
                    SectionErrorBanner(
                        "My Queue failed to refresh: ${state.queueError}",
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                }
            }

            // My Queue header
            item {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // a11y: heading() so TalkBack announces "My Queue, heading" on focus
                    Text(
                        "My Queue",
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.semantics { heading() },
                    )
                    TextButton(onClick = onNavigateToTickets) {
                        Text("View All")
                    }
                }
            }

            // [P0/P1] Empty state → shared EmptyState component.
            if (state.myQueue.isEmpty()) {
                item {
                    EmptyState(
                        icon = Icons.Default.ConfirmationNumber,
                        title = "All clear",
                        subtitle = "No tickets assigned to you",
                        includeWave = false,
                    )
                }
            } else {
                items(state.myQueue, key = { it.id }) { ticket ->
                    QueueTicketRow(
                        ticket = ticket,
                        onClick = { onNavigateToTicket(ticket.id) },
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                }
            }
        }

        // U9 fix: Needs Attention error banner in-place.
        if (state.attentionError != null) {
            item {
                SectionErrorBanner(
                    "Needs Attention failed to load: ${state.attentionError}",
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
        }

        // Needs Attention
        if (state.needsAttention.isNotEmpty()) {
            item {
                // a11y: heading() so TalkBack announces "Needs Attention, heading" on focus
                Text(
                    "Needs Attention",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                        .semantics { heading() },
                )
            }
            items(state.needsAttention, key = { "${it.type}:${it.message}" }) { item ->
                // [P2] WarningBg replaced with WarningAmber.copy(alpha=0.12f) so it
                // doesn't glow as a light-mode pastel on the dark OLED ramp.
                AttentionCard(
                    item = item,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
        }
    }
    }
    // Scrim: rendered after PullToRefreshBox so it sits above the list in Z-order.
    // Tapping collapses the FAB; only visible when FAB is expanded.
    if (fabExpandedState.value) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.scrim.copy(alpha = 0.32f))
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = { fabExpandedState.value = false },
                ),
        )
    }
    } // end scrim Box
    }
}

// ---------------------------------------------------------------------------
// Queue ticket row — BrandCard treatment + BrandStatusBadge
// ---------------------------------------------------------------------------

@Composable
private fun QueueTicketRow(
    ticket: TicketSummary,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            // a11y: merge children so TalkBack reads the ticket as one unit; Role.Button
            // signals it is actionable; contentDescription provides the full announcement.
            .semantics(mergeDescendants = true) {
                contentDescription = "Ticket ${ticket.orderId}, ${ticket.customerName}, status: ${ticket.statusName}. Tap to open."
                role = Role.Button
            }
            .clickable(onClick = onClick)
            .defaultMinSize(minHeight = 48.dp)
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outline,
                shape = MaterialTheme.shapes.medium,
            ),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(
            modifier = Modifier.padding(16.dp).fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                // Order ID in titleSmall — reads like a code/ID
                Text(
                    ticket.orderId,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    ticket.customerName,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(modifier = Modifier.width(12.dp))
            // [P1] BrandStatusBadge replaces raw color-parsed Surface pill
            BrandStatusBadge(
                label = ticket.statusName,
                status = ticket.statusName,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Attention card — WarningAmber dynamic alpha instead of hardcoded WarningBg
// ---------------------------------------------------------------------------

@Composable
private fun AttentionCard(item: AttentionItem, modifier: Modifier = Modifier) {
    // [P2] Dynamic alpha so the card reads correctly on the dark OLED ramp
    // rather than glowing with the light-mode #FEF3C7 pastel.
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = WarningAmber.copy(alpha = 0.12f),
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // decorative — non-clickable alert card; sibling item.message Text carries the announcement
            Icon(Icons.Default.Warning, contentDescription = null, tint = WarningAmber, modifier = Modifier.size(20.dp))
            Text(item.message, style = MaterialTheme.typography.bodySmall)
        }
    }
}

// ---------------------------------------------------------------------------
// SectionErrorBanner — toned down per spec
// ---------------------------------------------------------------------------

// U9 fix: in-place per-section error banner.
// [P1] Toned down: onErrorContainer at 90% alpha, 12sp, icon at 14dp.
@Composable
private fun SectionErrorBanner(message: String, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.errorContainer,
        shape = MaterialTheme.shapes.small,
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Default.ErrorOutline,
                // decorative — non-clickable section error banner; sibling message Text carries the announcement
                contentDescription = null,
                modifier = Modifier.size(14.dp),
                tint = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.9f),
            )
            Text(
                message,
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp),
                color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.9f),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// KpiCardView — BrandCard treatment + display-condensed value + breathing top pad
// ---------------------------------------------------------------------------

// [P1] BrandCard treatment: 1px outline border, no elevation shadow, 14dp radius.
// Display-condensed (headlineMedium = Barlow Condensed via Typography.kt) for value.
// All KPI values use primary purple — icon tint carries secondary differentiation.
// 20dp top padding so the icon breathes.
@Composable
fun KpiCardView(kpi: KpiCard, modifier: Modifier = Modifier) {
    // §3.1 / §26 — clickable tile wrapper. Only applied when the KpiCard provides
    // an onClick; inert tiles (e.g. Revenue Today) stay non-focusable so
    // TalkBack doesn't announce a button that does nothing.
    //
    // a11y: mergeDescendants collapses icon + value + label into one node so
    // TalkBack reads the tile as a single announcement rather than three
    // separate focus stops. contentDescription gives the full human-readable
    // string. Role.Button is only added on clickable tiles — inert tiles get
    // no role so TalkBack does not call them buttons.
    val semanticsModifier = if (kpi.onClick != null) {
        Modifier.semantics(mergeDescendants = true) {
            contentDescription = "${kpi.label}: ${kpi.value}. Tap to view list."
            role = Role.Button
        }
    } else {
        // a11y: inert tile — still merge so TalkBack reads value + label together,
        // but no Role.Button since there is no action.
        Modifier.semantics(mergeDescendants = true) {
            contentDescription = "${kpi.label}: ${kpi.value}."
        }
    }
    val clickModifier = if (kpi.onClick != null) {
        Modifier.clickable(onClick = kpi.onClick)
    } else {
        Modifier
    }
    Card(
        modifier = modifier
            // a11y: 48dp floor ensures the tile meets the Material 3 minimum touch target
            .defaultMinSize(minHeight = 48.dp)
            .then(semanticsModifier)
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outline,
                shape = MaterialTheme.shapes.medium,
            )
            .then(clickModifier),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 16.dp)) {
            kpi.icon()
            Spacer(modifier = Modifier.height(8.dp))
            // Monochrome + state: value color mirrors the icon tint (state hue
            // when non-zero, muted when zero). Keeps the grid calm on empty
            // screens and only surfaces color where it's load-bearing.
            Text(
                kpi.value,
                style = MaterialTheme.typography.headlineMedium, // Barlow Condensed via Typography
                color = kpi.iconTint,
            )
            Text(
                kpi.label,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
