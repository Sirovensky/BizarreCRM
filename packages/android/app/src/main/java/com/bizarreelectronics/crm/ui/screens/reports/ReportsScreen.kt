package com.bizarreelectronics.crm.ui.screens.reports

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.ReportApi
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class StatusCount(
    val id: Long,
    val name: String,
    val color: String,
    val count: Int,
)

data class ReportsUiState(
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val revenueToday: Double = 0.0,
    val openTickets: Int = 0,
    val closedToday: Int = 0,
    val ticketsCreatedToday: Int = 0,
    val statusCounts: List<StatusCount> = emptyList(),
    val staleTickets: Int = 0,
    val missingPartsCount: Int = 0,
    val overdueInvoices: Int = 0,
    val lowStockCount: Int = 0,
)

@HiltViewModel
class ReportsViewModel @Inject constructor(
    private val reportApi: ReportApi,
) : ViewModel() {

    private val _state = MutableStateFlow(ReportsUiState())
    val state: StateFlow<ReportsUiState> = _state.asStateFlow()

    init {
        loadData()
    }

    fun loadData() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            try {
                val dashboardDeferred = async { reportApi.getDashboard() }
                val attentionDeferred = async { reportApi.getNeedsAttention() }

                val dashboardRes = dashboardDeferred.await()
                val attentionRes = attentionDeferred.await()

                val dashData = dashboardRes.data ?: emptyMap()
                val attData = attentionRes.data ?: emptyMap()

                val statusCountsRaw = (dashData["status_counts"] as? List<*>) ?: emptyList<Any>()
                val parsedStatusCounts = statusCountsRaw.mapNotNull { entry ->
                    val map = entry as? Map<*, *> ?: return@mapNotNull null
                    StatusCount(
                        id = (map["id"] as? Number)?.toLong() ?: 0L,
                        name = (map["name"] as? String) ?: "Unknown",
                        color = (map["color"] as? String) ?: "#888888",
                        count = (map["count"] as? Number)?.toInt() ?: 0,
                    )
                }

                _state.update {
                    it.copy(
                        isLoading = false,
                        isRefreshing = false,
                        revenueToday = (dashData["revenue_today"] as? Number)?.toDouble() ?: 0.0,
                        openTickets = (dashData["open_tickets"] as? Number)?.toInt() ?: 0,
                        closedToday = (dashData["closed_today"] as? Number)?.toInt() ?: 0,
                        ticketsCreatedToday = (dashData["tickets_created_today"] as? Number)?.toInt() ?: 0,
                        statusCounts = parsedStatusCounts,
                        staleTickets = (attData["stale_tickets"] as? Number)?.toInt() ?: 0,
                        missingPartsCount = (attData["missing_parts_count"] as? Number)?.toInt() ?: 0,
                        overdueInvoices = (attData["overdue_invoices"] as? Number)?.toInt() ?: 0,
                        lowStockCount = (attData["low_stock_count"] as? Number)?.toInt() ?: 0,
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, isRefreshing = false, error = e.message ?: "Failed to load reports.") }
            }
        }
    }

    fun refresh() {
        _state.update { it.copy(isRefreshing = true) }
        loadData()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportsScreen(
    viewModel: ReportsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    var selectedTabIndex by remember { mutableIntStateOf(0) }
    val tabs = listOf("Sales", "Tickets", "Employees")

    Scaffold(
        topBar = { TopAppBar(title = { Text("Reports") }) },
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            TabRow(selectedTabIndex = selectedTabIndex) {
                tabs.forEachIndexed { index, title ->
                    Tab(
                        selected = selectedTabIndex == index,
                        onClick = { selectedTabIndex = index },
                        text = { Text(title) },
                    )
                }
            }

            PullToRefreshBox(
                isRefreshing = state.isRefreshing,
                onRefresh = { viewModel.refresh() },
                modifier = Modifier.fillMaxSize(),
            ) {
                if (state.isLoading && !state.isRefreshing) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                } else if (state.error != null) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(state.error ?: "Error", color = MaterialTheme.colorScheme.error)
                            Spacer(modifier = Modifier.height(8.dp))
                            OutlinedButton(onClick = { viewModel.loadData() }) { Text("Retry") }
                        }
                    }
                } else {
                    when (selectedTabIndex) {
                        0 -> SalesReportTab(state)
                        1 -> TicketsReportTab(state)
                        2 -> EmployeesReportTab()
                    }
                }
            }
        }
    }
}

@Composable
private fun SalesReportTab(state: ReportsUiState) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                SummaryCard(
                    value = "$${String.format("%.2f", state.revenueToday)}",
                    label = "Revenue Today",
                    modifier = Modifier.weight(1f),
                )
                SummaryCard(
                    value = "${state.openTickets}",
                    label = "Open Tickets",
                    modifier = Modifier.weight(1f),
                )
            }
        }

        // Needs attention
        if (state.staleTickets > 0 || state.missingPartsCount > 0 || state.overdueInvoices > 0 || state.lowStockCount > 0) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                ) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("Needs Attention", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        if (state.staleTickets > 0) {
                            Text("${state.staleTickets} stale tickets", style = MaterialTheme.typography.bodySmall)
                        }
                        if (state.missingPartsCount > 0) {
                            Text("${state.missingPartsCount} missing parts", style = MaterialTheme.typography.bodySmall)
                        }
                        if (state.overdueInvoices > 0) {
                            Text("${state.overdueInvoices} overdue invoices", style = MaterialTheme.typography.bodySmall)
                        }
                        if (state.lowStockCount > 0) {
                            Text("${state.lowStockCount} low stock items", style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TicketsReportTab(state: ReportsUiState) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                SummaryCard(
                    value = "${state.ticketsCreatedToday}",
                    label = "Created Today",
                    modifier = Modifier.weight(1f),
                )
                SummaryCard(
                    value = "${state.closedToday}",
                    label = "Closed Today",
                    modifier = Modifier.weight(1f),
                )
            }
        }
        item {
            SummaryCard(
                value = "${state.openTickets}",
                label = "Open Tickets",
                modifier = Modifier.fillMaxWidth(),
            )
        }

        if (state.statusCounts.isNotEmpty()) {
            item {
                Text(
                    "Status Breakdown",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
            items(state.statusCounts) { status ->
                StatusCountRow(status)
            }
        }
    }
}

@Composable
private fun StatusCountRow(status: StatusCount) {
    val color = try {
        Color(android.graphics.Color.parseColor(status.color))
    } catch (_: Exception) {
        MaterialTheme.colorScheme.primary
    }

    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(
                    modifier = Modifier.size(12.dp).clip(CircleShape).background(color),
                )
                Text(status.name, style = MaterialTheme.typography.bodyMedium)
            }
            Text(
                "${status.count}",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = color,
            )
        }
    }
}

@Composable
private fun EmployeesReportTab() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                Icons.Default.Engineering,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                "Employee Reports",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                "Coming soon",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun SummaryCard(
    value: String,
    label: String,
    modifier: Modifier = Modifier,
) {
    Card(modifier = modifier) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                value,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
            )
            Text(label, style = MaterialTheme.typography.bodySmall)
        }
    }
}
