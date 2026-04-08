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
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.api.ReportApi
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
    val error: String? = null,
)

data class TicketSummary(val id: Long, val orderId: String, val customerName: String, val deviceName: String, val statusName: String, val statusColor: String)
data class AttentionItem(val type: String, val message: String, val entityId: Long?)

@HiltViewModel
class DashboardViewModel @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val ticketApi: TicketApi,
    private val reportApi: ReportApi,
) : ViewModel() {

    private val _state = MutableStateFlow(DashboardUiState())
    val state = _state.asStateFlow()

    init {
        loadDashboard()
    }

    private fun loadDashboard() {
        viewModelScope.launch {
            var hasError = false
            val hour = java.time.LocalTime.now().hour
            val greetingText = when {
                hour < 12 -> "Good morning"
                hour < 17 -> "Good afternoon"
                else -> "Good evening"
            }
            val name = authPreferences.userFirstName ?: authPreferences.username ?: ""

            _state.value = _state.value.copy(greeting = "$greetingText, $name", error = null)

            // Fetch dashboard stats from reports endpoint
            try {
                val dashResponse = reportApi.getDashboard()
                val dashMap = dashResponse.data
                if (dashMap != null) {
                    val open = (dashMap["open_tickets"] as? Number)?.toInt() ?: 0
                    val revenue = (dashMap["revenue_today"] as? Number)?.toDouble() ?: 0.0
                    val appointments = (dashMap["appointments_today"] as? Number)?.toInt() ?: 0
                    _state.value = _state.value.copy(
                        openTickets = open,
                        revenueToday = revenue,
                        appointmentsToday = appointments,
                    )
                }
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "Failed to load stats: ${e.message}")
                hasError = true
            }

            // Fetch needs-attention for low stock count + attention items
            try {
                val attentionResponse = reportApi.getNeedsAttention()
                val attentionMap = attentionResponse.data
                if (attentionMap != null) {
                    val lowStock = (attentionMap["low_stock_count"] as? Number)?.toInt() ?: 0
                    val missingParts = (attentionMap["missing_parts_count"] as? Number)?.toInt() ?: 0
                    val staleTickets = (attentionMap["stale_tickets"] as? List<*>)?.size ?: 0
                    val overdueInvoices = (attentionMap["overdue_invoices"] as? List<*>)?.size ?: 0
                    val attentionItems = mutableListOf<AttentionItem>()
                    if (staleTickets > 0) attentionItems.add(AttentionItem("ticket", "$staleTickets stale tickets need attention", null))
                    if (missingParts > 0) attentionItems.add(AttentionItem("parts", "$missingParts parts missing across open tickets", null))
                    if (overdueInvoices > 0) attentionItems.add(AttentionItem("invoice", "$overdueInvoices overdue invoices", null))
                    _state.value = _state.value.copy(
                        lowStockCount = lowStock,
                        needsAttention = attentionItems,
                    )
                }
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "Failed to load needs-attention: ${e.message}")
                hasError = true
            }

            // Load assigned tickets for "My Queue"
            try {
                val userId = authPreferences.userId
                val response = ticketApi.getTickets(mapOf(
                    "assigned_to" to userId.toString(),
                    "status" to "open",
                    "pagesize" to "10",
                ))
                val ticketData = response.data
                if (ticketData != null) {
                    _state.value = _state.value.copy(
                        myQueue = ticketData.tickets.map { t ->
                            TicketSummary(
                                id = t.id,
                                orderId = t.orderId,
                                customerName = t.customerName,
                                deviceName = t.firstDevice?.deviceName ?: "",
                                statusName = t.statusName ?: "",
                                statusColor = t.statusColor ?: "#6b7280",
                            )
                        },
                    )
                }
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "Failed to load queue: ${e.message}")
                hasError = true
            }

            _state.value = _state.value.copy(
                isLoading = false,
                isRefreshing = false,
                error = if (hasError) "Failed to load data. Pull to refresh." else null,
            )
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
        // Error banner
        if (state.error != null) {
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
                            state.error ?: "",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                        )
                    }
                }
            }
        }

        // Greeting
        item {
            Column(modifier = Modifier.padding(top = 8.dp)) {
                Text(
                    state.greeting,
                    style = MaterialTheme.typography.headlineMedium,
                )
                Text(
                    java.time.LocalDate.now().format(java.time.format.DateTimeFormatter.ofPattern("EEEE, MMMM d")),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
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
                            Text(ticket.deviceName, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
