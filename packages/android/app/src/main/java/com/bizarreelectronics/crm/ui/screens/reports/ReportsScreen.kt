package com.bizarreelectronics.crm.ui.screens.reports

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
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
import com.bizarreelectronics.crm.data.repository.DashboardRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.theme.ErrorRed
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import javax.inject.Inject

// ─── Constants ───────────────────────────────────────────────────────────────

private const val MILLIS_PER_DAY = 86_400_000L

/** Server-format YYYY-MM-DD. Fixed to UTC so the wire format never shifts. */
private val SERVER_DATE_FORMAT: SimpleDateFormat
    get() = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

/** Display-friendly date for chip labels. */
private val DISPLAY_DATE_FORMAT: SimpleDateFormat
    get() = SimpleDateFormat("MMM d, yyyy", Locale.US)

private fun formatServerDate(millis: Long): String =
    SERVER_DATE_FORMAT.format(Date(millis))

private fun formatDisplayDate(millis: Long): String =
    DISPLAY_DATE_FORMAT.format(Date(millis))

private fun startOfTodayMillis(): Long {
    val cal = Calendar.getInstance().apply {
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }
    return cal.timeInMillis
}

private fun daysAgoMillis(days: Int): Long = startOfTodayMillis() - days * MILLIS_PER_DAY

// ─── Quick range presets ─────────────────────────────────────────────────────

enum class DateRangePreset(val label: String) {
    TODAY("Today"),
    WEEK("Week"),
    MONTH("Month"),
    YEAR("Year"),
    CUSTOM("Custom"),
}

private data class DateRange(val fromMillis: Long, val toMillis: Long)

private fun rangeFor(preset: DateRangePreset): DateRange? {
    val today = startOfTodayMillis()
    return when (preset) {
        DateRangePreset.TODAY -> DateRange(today, today)
        DateRangePreset.WEEK -> DateRange(daysAgoMillis(6), today)
        DateRangePreset.MONTH -> DateRange(daysAgoMillis(29), today)
        DateRangePreset.YEAR -> DateRange(daysAgoMillis(364), today)
        DateRangePreset.CUSTOM -> null
    }
}

// ─── Models ──────────────────────────────────────────────────────────────────

data class StatusCount(
    val id: Long,
    val name: String,
    val color: String,
    val count: Int,
)

data class PaymentMethodBreakdown(
    val method: String,
    val revenue: Double,
    val count: Int,
)

data class SalesReport(
    val totalRevenue: Double = 0.0,
    val transactionCount: Int = 0,
    val averageTransaction: Double = 0.0,
    val uniqueCustomers: Int = 0,
    val previousRevenue: Double = 0.0,
    val revenueChangePct: Double? = null,
    val paymentMethods: List<PaymentMethodBreakdown> = emptyList(),
    val isFromCache: Boolean = false,
)

data class ReportsUiState(
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val isOffline: Boolean = false,
    // Dashboard / Needs Attention
    val revenueToday: Double = 0.0,
    val openTickets: Int = 0,
    val staleTickets: Int = 0,
    val missingPartsCount: Int = 0,
    val overdueInvoices: Int = 0,
    val lowStockCount: Int = 0,
    // Sales tab — date range
    val selectedPreset: DateRangePreset = DateRangePreset.MONTH,
    val fromDate: Long = daysAgoMillis(29),
    val toDate: Long = startOfTodayMillis(),
    val isSalesLoading: Boolean = false,
    val salesError: String? = null,
    val salesReport: SalesReport = SalesReport(),
)

// ─── ViewModel ───────────────────────────────────────────────────────────────

@HiltViewModel
class ReportsViewModel @Inject constructor(
    private val dashboardRepository: DashboardRepository,
    private val reportApi: ReportApi,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(ReportsUiState())
    val state: StateFlow<ReportsUiState> = _state.asStateFlow()

    init {
        loadData()
        loadSalesReport()
        observeOnlineState()
    }

    private fun observeOnlineState() {
        viewModelScope.launch {
            serverMonitor.isEffectivelyOnline.collect { online ->
                _state.update { it.copy(isOffline = !online) }
            }
        }
    }

    fun loadData() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            try {
                val statsDeferred = async { dashboardRepository.getDashboardStats() }
                val attentionDeferred = async { dashboardRepository.getNeedsAttention() }

                val stats = statsDeferred.await()
                val attention = attentionDeferred.await()

                _state.update {
                    it.copy(
                        isLoading = false,
                        isRefreshing = false,
                        revenueToday = stats.revenueToday,
                        openTickets = stats.openTickets,
                        staleTickets = attention.staleTicketsCount,
                        missingPartsCount = attention.missingPartsCount,
                        overdueInvoices = attention.overdueInvoicesCount,
                        lowStockCount = attention.lowStockCount,
                    )
                }
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        isLoading = false,
                        isRefreshing = false,
                        error = e.message ?: "Failed to load reports.",
                    )
                }
            }
        }
    }

    fun refresh() {
        _state.update { it.copy(isRefreshing = true) }
        loadData()
        loadSalesReport()
    }

    fun selectPreset(preset: DateRangePreset) {
        val range = rangeFor(preset) ?: run {
            // CUSTOM — caller will open the picker; just record the selection
            _state.update { it.copy(selectedPreset = preset) }
            return
        }
        _state.update {
            it.copy(
                selectedPreset = preset,
                fromDate = range.fromMillis,
                toDate = range.toMillis,
            )
        }
        loadSalesReport()
    }

    fun setCustomRange(fromMillis: Long, toMillis: Long) {
        val from = minOf(fromMillis, toMillis)
        val to = maxOf(fromMillis, toMillis)
        _state.update {
            it.copy(
                selectedPreset = DateRangePreset.CUSTOM,
                fromDate = from,
                toDate = to,
            )
        }
        loadSalesReport()
    }

    fun loadSalesReport() {
        viewModelScope.launch {
            _state.update { it.copy(isSalesLoading = true, salesError = null) }
            if (!serverMonitor.isEffectivelyOnline.value) {
                _state.update {
                    it.copy(
                        isSalesLoading = false,
                        salesReport = it.salesReport.copy(isFromCache = true),
                        salesError = null,
                    )
                }
                return@launch
            }
            try {
                val current = _state.value
                val response = reportApi.getSalesReport(
                    mapOf(
                        "from_date" to formatServerDate(current.fromDate),
                        "to_date" to formatServerDate(current.toDate),
                    )
                )
                val report = parseSalesResponse(response.data)
                _state.update {
                    it.copy(
                        isSalesLoading = false,
                        salesReport = report,
                    )
                }
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        isSalesLoading = false,
                        salesError = e.message ?: "Failed to load sales report",
                    )
                }
            }
        }
    }

    private fun parseSalesResponse(data: Map<String, Any>?): SalesReport {
        if (data == null) return SalesReport()
        val totalsRaw = data["totals"] as? Map<*, *>
        val totalRevenue = (totalsRaw?.get("total_revenue") as? Number)?.toDouble() ?: 0.0
        val totalInvoices = (totalsRaw?.get("total_invoices") as? Number)?.toInt() ?: 0
        val uniqueCustomers = (totalsRaw?.get("unique_customers") as? Number)?.toInt() ?: 0
        val previousRevenue = (totalsRaw?.get("previous_revenue") as? Number)?.toDouble() ?: 0.0
        val changePct = (totalsRaw?.get("revenue_change_pct") as? Number)?.toDouble()
        val avg = if (totalInvoices > 0) totalRevenue / totalInvoices else 0.0

        val byMethodRaw = data["byMethod"] as? List<*> ?: emptyList<Any>()
        val methods = byMethodRaw.mapNotNull { row ->
            val map = row as? Map<*, *> ?: return@mapNotNull null
            PaymentMethodBreakdown(
                method = (map["method"] as? String) ?: "Other",
                revenue = (map["revenue"] as? Number)?.toDouble() ?: 0.0,
                count = (map["count"] as? Number)?.toInt() ?: 0,
            )
        }

        return SalesReport(
            totalRevenue = totalRevenue,
            transactionCount = totalInvoices,
            averageTransaction = avg,
            uniqueCustomers = uniqueCustomers,
            previousRevenue = previousRevenue,
            revenueChangePct = changePct,
            paymentMethods = methods,
            isFromCache = false,
        )
    }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportsScreen(
    viewModel: ReportsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    var selectedTabIndex by remember { mutableIntStateOf(0) }
    val tabs = listOf("Dashboard", "Sales", "Needs Attention")

    Scaffold(
        topBar = { BrandTopAppBar(title = "Reports") },
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            // CROSS37: TabRow labels all rendered in primary color; only the
            // underline indicated the active tab. Conditionally color the label
            // text via the `selected` prop so active=primary and
            // inactive=onSurfaceVariant — underline (already primary) + text
            // color both carry the active-state signal.
            TabRow(selectedTabIndex = selectedTabIndex) {
                tabs.forEachIndexed { index, title ->
                    val isSelected = selectedTabIndex == index
                    Tab(
                        selected = isSelected,
                        onClick = { selectedTabIndex = index },
                        text = {
                            Text(
                                title,
                                color = if (isSelected) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                },
                            )
                        },
                        selectedContentColor = MaterialTheme.colorScheme.primary,
                        unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            PullToRefreshBox(
                isRefreshing = state.isRefreshing,
                onRefresh = { viewModel.refresh() },
                modifier = Modifier.fillMaxSize(),
            ) {
                if (state.isLoading && !state.isRefreshing && selectedTabIndex != 1) {
                    BrandSkeleton(
                        rows = 4,
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                    )
                } else if (state.error != null && selectedTabIndex != 1) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        ErrorState(
                            message = state.error ?: "Failed to load reports.",
                            onRetry = { viewModel.loadData() },
                        )
                    }
                } else {
                    when (selectedTabIndex) {
                        0 -> DashboardReportTab(state)
                        1 -> SalesReportTab(
                            state = state,
                            onPresetSelected = viewModel::selectPreset,
                            onCustomRangeSelected = viewModel::setCustomRange,
                            onRetry = viewModel::loadSalesReport,
                        )
                        2 -> NeedsAttentionTab(state)
                    }
                }
            }
        }
    }
}

// ─── Dashboard tab ───────────────────────────────────────────────────────────

@Composable
private fun DashboardReportTab(state: ReportsUiState) {
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
                    // @audit-fixed: was a hand-rolled "$%.2f" — switching to
                    // CurrencyFormatter centralises money formatting and means
                    // future locale/currency-symbol changes only need to land in
                    // one place. The locale-aware formatter also gives proper
                    // grouping ("$1,234.00") which the old code lacked.
                    value = com.bizarreelectronics.crm.util.CurrencyFormatter.format(state.revenueToday),
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
    }
}

// ─── Sales tab (date-ranged) ─────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SalesReportTab(
    state: ReportsUiState,
    onPresetSelected: (DateRangePreset) -> Unit,
    onCustomRangeSelected: (Long, Long) -> Unit,
    onRetry: () -> Unit,
) {
    // @audit-fixed: dialog visibility was lost on rotation — if the user
    // rotated the device while the date range picker was open it silently
    // vanished. rememberSaveable preserves the open/closed state across
    // configuration changes so the picker stays open if the user spins the
    // phone mid-edit.
    var showDatePicker by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(false) }

    if (showDatePicker) {
        DateRangePickerDialog(
            initialFromMillis = state.fromDate,
            initialToMillis = state.toDate,
            onDismiss = { showDatePicker = false },
            onConfirm = { from, to ->
                onCustomRangeSelected(from, to)
                showDatePicker = false
            },
        )
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Quick range chips
        item {
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(DateRangePreset.values()) { preset ->
                    FilterChip(
                        selected = state.selectedPreset == preset,
                        onClick = {
                            if (preset == DateRangePreset.CUSTOM) {
                                showDatePicker = true
                            }
                            onPresetSelected(preset)
                        },
                        label = { Text(preset.label) },
                    )
                }
            }
        }

        // Selected range display
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                ),
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(
                        "Date Range",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        "${formatDisplayDate(state.fromDate)} – ${formatDisplayDate(state.toDate)}",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }

        if (state.isOffline) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                    ),
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.CloudOff,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onErrorContainer,
                        )
                        Text(
                            "Offline – showing cached data",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                        )
                    }
                }
            }
        }

        when {
            state.isSalesLoading -> {
                item {
                    BrandSkeleton(
                        rows = 4,
                        modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                    )
                }
            }
            state.salesError != null -> {
                item {
                    ErrorState(
                        message = state.salesError ?: "Failed to load sales report.",
                        onRetry = onRetry,
                    )
                }
            }
            else -> {
                val report = state.salesReport
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        SummaryCard(
                            // @audit-fixed: hand-rolled "$%.2f" replaced with CurrencyFormatter
                            value = com.bizarreelectronics.crm.util.CurrencyFormatter.format(report.totalRevenue),
                            label = "Total Revenue",
                            modifier = Modifier.weight(1f),
                        )
                        SummaryCard(
                            value = "${report.transactionCount}",
                            label = "Transactions",
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        SummaryCard(
                            // @audit-fixed: hand-rolled "$%.2f" replaced with CurrencyFormatter
                            value = com.bizarreelectronics.crm.util.CurrencyFormatter.format(report.averageTransaction),
                            label = "Avg Transaction",
                            modifier = Modifier.weight(1f),
                        )
                        SummaryCard(
                            value = "${report.uniqueCustomers}",
                            label = "Unique Customers",
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
                if (report.revenueChangePct != null) {
                    item { RevenueChangeCard(changePct = report.revenueChangePct) }
                }
                if (report.paymentMethods.isNotEmpty()) {
                    item {
                        Text(
                            "Payment Methods",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                    }
                    items(report.paymentMethods) { method ->
                        PaymentMethodRow(method)
                    }
                }
            }
        }
    }
}

@Composable
private fun RevenueChangeCard(changePct: Double) {
    val isPositive = changePct >= 0
    // Use semantic brand tokens — not tailwind hex literals.
    // Alpha-tinted bg keeps the OLED-friendly dark surface; foreground uses
    // the full semantic color for sufficient contrast (WCAG AA).
    val containerColor = if (isPositive) {
        SuccessGreen.copy(alpha = 0.15f)
    } else {
        ErrorRed.copy(alpha = 0.15f)
    }
    val textColor = if (isPositive) SuccessGreen else ErrorRed
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = containerColor),
    ) {
        Row(
            modifier = Modifier.padding(16.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                if (isPositive) Icons.Default.TrendingUp else Icons.Default.TrendingDown,
                contentDescription = null,
                tint = textColor,
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "vs Previous Period",
                    style = MaterialTheme.typography.labelSmall,
                    color = textColor,
                )
                Text(
                    "${if (isPositive) "+" else ""}${String.format(Locale.US, "%.1f", changePct)}%",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = textColor,
                )
            }
        }
    }
}

@Composable
private fun PaymentMethodRow(method: PaymentMethodBreakdown) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column {
                Text(method.method, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                Text(
                    "${method.count} transactions",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                // @audit-fixed: hand-rolled "$%.2f" replaced with CurrencyFormatter
                com.bizarreelectronics.crm.util.CurrencyFormatter.format(method.revenue),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

// ─── Date range picker dialog ────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DateRangePickerDialog(
    initialFromMillis: Long,
    initialToMillis: Long,
    onDismiss: () -> Unit,
    onConfirm: (Long, Long) -> Unit,
) {
    val pickerState = rememberDateRangePickerState(
        initialSelectedStartDateMillis = initialFromMillis,
        initialSelectedEndDateMillis = initialToMillis,
    )
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                onClick = {
                    val from = pickerState.selectedStartDateMillis
                    val to = pickerState.selectedEndDateMillis
                    if (from != null && to != null) {
                        onConfirm(from, to)
                    } else if (from != null) {
                        onConfirm(from, from)
                    } else {
                        onDismiss()
                    }
                },
                enabled = pickerState.selectedStartDateMillis != null,
            ) {
                Text("OK")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    ) {
        DateRangePicker(
            state = pickerState,
            modifier = Modifier.fillMaxWidth().heightIn(max = 560.dp),
            title = { Text("Select date range", modifier = Modifier.padding(16.dp)) },
        )
    }
}

// ─── Needs Attention tab ─────────────────────────────────────────────────────

@Composable
private fun NeedsAttentionTab(state: ReportsUiState) {
    val hasAnyAlerts = state.staleTickets > 0 ||
        state.missingPartsCount > 0 ||
        state.overdueInvoices > 0 ||
        state.lowStockCount > 0

    if (!hasAnyAlerts) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    Icons.Default.CheckCircle,
                    contentDescription = null,
                    modifier = Modifier.size(48.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    "All clear",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    "No items need attention",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
        }
        return
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (state.staleTickets > 0) {
            item {
                AttentionRow(
                    icon = Icons.Default.Schedule,
                    label = "Stale Tickets",
                    count = state.staleTickets,
                )
            }
        }
        if (state.missingPartsCount > 0) {
            item {
                AttentionRow(
                    icon = Icons.Default.Build,
                    label = "Missing Parts",
                    count = state.missingPartsCount,
                )
            }
        }
        if (state.overdueInvoices > 0) {
            item {
                AttentionRow(
                    icon = Icons.Default.Receipt,
                    label = "Overdue Invoices",
                    count = state.overdueInvoices,
                )
            }
        }
        if (state.lowStockCount > 0) {
            item {
                AttentionRow(
                    icon = Icons.Default.Inventory,
                    label = "Low Stock Items",
                    count = state.lowStockCount,
                )
            }
        }
    }
}

@Composable
private fun AttentionRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    count: Int,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer,
        ),
    ) {
        Row(
            modifier = Modifier.padding(16.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onErrorContainer,
            )
            Text(
                label,
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onErrorContainer,
            )
            Text(
                "$count",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onErrorContainer,
            )
        }
    }
}

// ─── Status row (kept for backward compat, used by future tabs) ──────────────

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

// ─── Shared cards ────────────────────────────────────────────────────────────

@Composable
private fun SummaryCard(
    value: String,
    label: String,
    modifier: Modifier = Modifier,
) {
    // CROSS36: was primaryContainer (brown/tan) which read as "milk chocolate"
    // — out of place in a dark UI. Switched to dark-surface + 1dp outline to
    // match DashboardScreen.KpiCardView; a primary-tinted value keeps the KPI
    // readable as the emphatic cell.
    Card(
        modifier = modifier
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
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                value,
                style = MaterialTheme.typography.headlineMedium, // Barlow Condensed SemiBold
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                label,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}
