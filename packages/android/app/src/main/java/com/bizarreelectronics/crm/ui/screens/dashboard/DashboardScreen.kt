package com.bizarreelectronics.crm.ui.screens.dashboard

import androidx.compose.foundation.clickable
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.repository.DashboardRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class KpiCard(val label: String, val value: String, val color: Color, val icon: @Composable () -> Unit)

data class DashboardUiState(
    val greeting: String = "",
    val openTickets: Int = 0,
    val revenueToday: Double = 0.0,
    val appointmentsToday: Int = 0,
    val lowStockCount: Int = 0,
    val myQueue: List<TicketSummary> = emptyList(),
    val needsAttention: List<AttentionItem> = emptyList(),
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
) : ViewModel() {

    private val _state = MutableStateFlow(DashboardUiState())
    val state = _state.asStateFlow()

    init {
        loadDashboard()
        collectMyQueue()
    }

    private fun loadDashboard() {
        viewModelScope.launch {
            val name = authPreferences.userFirstName ?: authPreferences.username ?: ""
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
    viewModel: DashboardViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    val kpis = listOf(
        KpiCard("Open Tickets", state.openTickets.toString(), MaterialTheme.colorScheme.primary) {
            Icon(Icons.Default.ConfirmationNumber, null, tint = MaterialTheme.colorScheme.primary)
        },
        KpiCard("Revenue Today", "$${String.format("%.2f", state.revenueToday)}", SuccessGreen) {
            Icon(Icons.Default.AttachMoney, null, tint = SuccessGreen)
        },
        KpiCard("Appointments", state.appointmentsToday.toString(), InfoBlue) {
            Icon(Icons.Default.CalendarToday, null, tint = InfoBlue)
        },
        KpiCard("Low Stock", state.lowStockCount.toString(), WarningAmber) {
            Icon(Icons.Default.Warning, null, tint = WarningAmber)
        },
    )

    PullToRefreshBox(
        isRefreshing = state.isRefreshing,
        onRefresh = { viewModel.refresh() },
        modifier = Modifier.fillMaxSize(),
    ) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // U9 fix: top-of-screen summary banner only appears if ANY section
        // failed, and each failing section also gets its own in-place banner
        // below. This tells users exactly which chunk of the dashboard is
        // stale instead of a generic "some data may be outdated" soup.
        if (state.hasAnyError) {
            item {
                Surface(
                    modifier = Modifier.fillMaxWidth(),
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
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onErrorContainer,
                        )
                        Text(
                            "Some sections failed to load. Pull to refresh.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                        )
                    }
                }
            }
        }

        // Greeting
        item {
            // U12 fix: the date is computed ONCE when this composable enters
            // composition, not every recomposition. Since the dashboard is
            // usually open for minutes not hours, recomputing once is fine.
            // The greeting itself lives in state and only updates on refresh.
            val todayFormatted = remember {
                java.time.LocalDate.now()
                    .format(java.time.format.DateTimeFormatter.ofPattern("EEEE, MMMM d"))
            }
            Column(modifier = Modifier.padding(top = 8.dp)) {
                Text(
                    state.greeting,
                    style = MaterialTheme.typography.headlineMedium,
                )
                Text(
                    todayFormatted,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        // U9 fix: KPI stats error banner in the KPI section.
        if (state.statsError != null) {
            item { SectionErrorBanner("KPIs failed to load: ${state.statsError}") }
        }

        // KPI Cards — 2x2 grid
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                kpis.take(2).forEach { kpi ->
                    KpiCardView(kpi, modifier = Modifier.weight(1f))
                }
            }
        }
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                kpis.drop(2).forEach { kpi ->
                    KpiCardView(kpi, modifier = Modifier.weight(1f))
                }
            }
        }

        // U9 fix: My Queue error banner in-place.
        if (state.queueError != null) {
            item { SectionErrorBanner("My Queue failed to refresh: ${state.queueError}") }
        }

        // My Queue
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("My Queue", style = MaterialTheme.typography.titleMedium)
                TextButton(onClick = onNavigateToTickets) {
                    Text("View All")
                }
            }
        }

        if (state.myQueue.isEmpty()) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                ) {
                    Box(
                        modifier = Modifier.fillMaxWidth().padding(32.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("No tickets assigned to you", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        } else {
            items(state.myQueue) { ticket ->
                Card(
                    modifier = Modifier.fillMaxWidth().clickable { onNavigateToTicket(ticket.id) },
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp).fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column {
                            Text(ticket.orderId, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                            Text(ticket.customerName, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        run {
                            val queueStatusBg = try { Color(android.graphics.Color.parseColor(ticket.statusColor)) } catch (_: Exception) { MaterialTheme.colorScheme.primary }
                            Surface(
                                shape = MaterialTheme.shapes.small,
                                color = queueStatusBg,
                            ) {
                                Text(
                                    ticket.statusName,
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = contrastTextColor(queueStatusBg),
                                )
                            }
                        }
                    }
                }
            }
        }

        // U9 fix: Needs Attention error banner in-place.
        if (state.attentionError != null) {
            item { SectionErrorBanner("Needs Attention failed to load: ${state.attentionError}") }
        }

        // Needs Attention
        if (state.needsAttention.isNotEmpty()) {
            item {
                Text("Needs Attention", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp))
            }
            items(state.needsAttention) { item ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = WarningBg),
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Default.Warning, null, tint = WarningAmber, modifier = Modifier.size(20.dp))
                        Text(item.message, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
    }
}

// U9 fix: in-place per-section error banner. Red container + icon + text.
@Composable
private fun SectionErrorBanner(message: String) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
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
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.onErrorContainer,
            )
            Text(
                message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer,
            )
        }
    }
}

@Composable
fun KpiCardView(kpi: KpiCard, modifier: Modifier = Modifier) {
    Card(modifier = modifier) {
        Column(modifier = Modifier.padding(16.dp)) {
            kpi.icon()
            Spacer(modifier = Modifier.height(8.dp))
            Text(kpi.value, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, color = kpi.color)
            Text(kpi.label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
