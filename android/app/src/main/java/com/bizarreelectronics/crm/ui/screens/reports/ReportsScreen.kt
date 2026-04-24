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
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
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
    // Overview / charts tab — §15 Vico charts
    val salesByDay: List<SalesByDayPoint> = emptyList(),
    val revenueOverTime: List<RevenueOverTimePoint> = emptyList(),
    val categoryBreakdown: List<CategoryBreakdownSlice> = emptyList(),
)

// ─── ViewModel ───────────────────────────────────────────────────────────────

@HiltViewModel
class ReportsViewModel @Inject constructor(
    private val dashboardRepository: DashboardRepository,
    private val reportApi: ReportApi,
    private val serverMonitor: ServerReachabilityMonitor,
    val appPreferences: AppPreferences,
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

    /**
     * Parses the `/reports/sales` response into a [SalesReport] and chart data.
     *
     * Chart mappings (§15):
     *   - [SalesByDayPoint]        — from `data.rows[].{ period, revenue }`. Revenue is
     *     stored in dollars from the server; we convert to cents (× 100) to keep the
     *     chart data as Long integers and avoid floating-point drift in axis labels.
     *   - [RevenueOverTimePoint]   — same rows, same conversion.
     *   - [CategoryBreakdownSlice] — from `data.byMethod[].{ method, revenue }`. Colour
     *     assignment is index-based using a fixed palette; the call site resolves
     *     MaterialTheme tokens before constructing slices.
     *
     * If `data.rows` is absent (e.g. old server version), chart lists default to empty.
     */
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

        // ── Chart data — parsed from rows, not totals ────────────────────────
        // TODO(§15-drill): wire category breakdown to actual service-category data
        //   once /reports/services endpoint is available. For now, payment-method
        //   revenue breakdown is a reasonable proxy for category breakdown.
        val rowsRaw = data["rows"] as? List<*> ?: emptyList<Any>()
        val salesByDay = rowsRaw.mapNotNull { row ->
            val map = row as? Map<*, *> ?: return@mapNotNull null
            val period = map["period"] as? String ?: return@mapNotNull null
            val revenueDollars = (map["revenue"] as? Number)?.toDouble() ?: 0.0
            SalesByDayPoint(
                isoDate = period,
                totalCents = (revenueDollars * 100).toLong(),
            )
        }
        val revenueOverTime = rowsRaw.mapNotNull { row ->
            val map = row as? Map<*, *> ?: return@mapNotNull null
            val period = map["period"] as? String ?: return@mapNotNull null
            val revenueDollars = (map["revenue"] as? Number)?.toDouble() ?: 0.0
            RevenueOverTimePoint(
                isoDate = period,
                revenueCents = (revenueDollars * 100).toLong(),
            )
        }

        // Update state with chart data (immutably via _state.update)
        _state.update { current ->
            current.copy(
                salesByDay = salesByDay,
                revenueOverTime = revenueOverTime,
                // categoryBreakdown colours are resolved in the composable layer;
                // store as raw breakdown here, composable maps colours from theme
                categoryBreakdown = emptyList(), // resolved in OverviewChartsTab
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
    // "Overview" tab (index 1) hosts the §15 Vico charts.
    // Existing indices shifted: Dashboard=0, Overview=1, Sales=2, Needs Attention=3.
    val tabs = listOf("Dashboard", "Overview", "Sales", "Needs Attention")

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
                        // a11y: Role.Tab + explicit selection announcement so TalkBack says
                        // "<tab name> tab, selected/not selected" rather than just the label.
                        modifier = Modifier.semantics {
                            role = Role.Tab
                            contentDescription = if (isSelected) {
                                "$title tab, selected"
                            } else {
                                "$title tab, not selected"
                            }
                        },
                    )
                }
            }

            PullToRefreshBox(
                isRefreshing = state.isRefreshing,
                onRefresh = { viewModel.refresh() },
                modifier = Modifier.fillMaxSize(),
            ) {
                // Sales tab index is now 2 (Overview added at 1).
                val isSalesTab = selectedTabIndex == 2
                if (state.isLoading && !state.isRefreshing && !isSalesTab) {
                    // a11y: mergeDescendants so TalkBack announces "Loading report" as a single item.
                    Box(
                        modifier = Modifier.semantics(mergeDescendants = true) {
                            contentDescription = "Loading report"
                        },
                    ) {
                        BrandSkeleton(
                            rows = 4,
                            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                        )
                    }
                } else if (state.error != null && !isSalesTab) {
                    // a11y: liveRegion=Assertive so TalkBack immediately interrupts and announces the error.
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics { liveRegion = LiveRegionMode.Assertive },
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Failed to load reports.",
                            onRetry = { viewModel.loadData() },
                        )
                    }
                } else {
                    when (selectedTabIndex) {
                        0 -> DashboardReportTab(state)
                        1 -> OverviewChartsTab(
                            state = state,
                            appPreferences = viewModel.appPreferences,
                        )
                        2 -> SalesReportTab(
                            state = state,
                            onPresetSelected = viewModel::selectPreset,
                            onCustomRangeSelected = viewModel::setCustomRange,
                            onRetry = viewModel::loadSalesReport,
                        )
                        3 -> NeedsAttentionTab(state)
                    }
                }
            }
        }
    }
}

// ─── Overview / Charts tab (§15 Vico charts) ─────────────────────────────────

/**
 * Stacks the three Vico chart composables vertically inside a [LazyColumn].
 *
 * Data is mapped from [ReportsUiState]:
 *   - salesByDay / revenueOverTime: populated by [ReportsViewModel.parseSalesResponse]
 *     after a successful /reports/sales fetch. Empty lists show "No data" placeholders.
 *   - categoryBreakdown: derived here from [ReportsUiState.salesReport.paymentMethods]
 *     (a proxy until a dedicated /reports/services endpoint is available — see TODO above).
 *
 * The [AppPreferences] reference is needed by [SalesByDayBarChart] and
 * [RevenueOverTimeLineChart] to honour the ReduceMotion preference.
 */
@Composable
private fun OverviewChartsTab(
    state: ReportsUiState,
    appPreferences: AppPreferences,
) {
    val primary = MaterialTheme.colorScheme.primary
    val secondary = MaterialTheme.colorScheme.secondary
    val tertiary = MaterialTheme.colorScheme.tertiary
    val error = MaterialTheme.colorScheme.error
    val outline = MaterialTheme.colorScheme.outline

    // Map payment-method breakdown to CategoryBreakdownSlice for the pie chart.
    // Colours cycle through 5 theme tokens; remaining slices reuse from the start.
    val themeColors = remember(primary, secondary, tertiary, error, outline) {
        listOf(primary, secondary, tertiary, error, outline)
    }
    val categorySlices = remember(state.salesReport.paymentMethods, themeColors) {
        state.salesReport.paymentMethods.mapIndexed { index, method ->
            CategoryBreakdownSlice(
                label = method.method,
                value = method.revenue,
                color = themeColors[index % themeColors.size],
            )
        }
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
        contentPadding = PaddingValues(vertical = 16.dp),
    ) {
        item {
            // a11y: heading() on the section title column so TalkBack users can jump between chart sections.
            ChartSection(title = "Sales by Period") {
                SalesByDayBarChart(
                    points = state.salesByDay,
                    appPreferences = appPreferences,
                )
            }
        }
        item {
            // a11y: heading() on the section title column so TalkBack users can jump between chart sections.
            ChartSection(title = "Revenue Over Time") {
                RevenueOverTimeLineChart(
                    points = state.revenueOverTime,
                    appPreferences = appPreferences,
                )
            }
        }
        item {
            // a11y: heading() on the section title column so TalkBack users can jump between chart sections.
            ChartSection(title = "Payment Method Breakdown") {
                CategoryBreakdownPieChart(slices = categorySlices)
            }
        }
        // Spacer so the last card is not clipped by system navigation bar
        item { Spacer(modifier = Modifier.height(8.dp)) }
    }
}

/** Thin section container: title + content card. */
@Composable
private fun ChartSection(
    title: String,
    content: @Composable () -> Unit,
) {
    // a11y: heading() on the outer Column so TalkBack navigation-by-heading jumps to each chart section.
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.semantics { heading() },
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = MaterialTheme.shapes.medium,
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surface,
            ),
            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        ) {
            Box(modifier = Modifier.padding(12.dp)) {
                content()
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
                val revenueFormatted = com.bizarreelectronics.crm.util.CurrencyFormatter.format(state.revenueToday)
                SummaryCard(
                    // @audit-fixed: was a hand-rolled "$%.2f" — switching to
                    // CurrencyFormatter centralises money formatting and means
                    // future locale/currency-symbol changes only need to land in
                    // one place. The locale-aware formatter also gives proper
                    // grouping ("$1,234.00") which the old code lacked.
                    value = revenueFormatted,
                    label = "Revenue Today",
                    // a11y: liveRegion=Polite + contentDescription so TalkBack announces updated KPI value.
                    a11yDescription = "Revenue Today: $revenueFormatted",
                    modifier = Modifier.weight(1f),
                )
                SummaryCard(
                    value = "${state.openTickets}",
                    label = "Open Tickets",
                    // a11y: liveRegion=Polite + contentDescription so TalkBack announces updated KPI value.
                    a11yDescription = "Open Tickets: ${state.openTickets}",
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
                items(DateRangePreset.values(), key = { it }) { preset ->
                    val isSelected = state.selectedPreset == preset
                    FilterChip(
                        selected = isSelected,
                        onClick = {
                            if (preset == DateRangePreset.CUSTOM) {
                                showDatePicker = true
                            }
                            onPresetSelected(preset)
                        },
                        label = { Text(preset.label) },
                        // a11y: Role.Button + selection state so TalkBack announces
                        // "<preset> period, selected/not selected. Tap to select."
                        modifier = Modifier.semantics {
                            role = Role.Button
                            contentDescription = if (isSelected) {
                                "${preset.label} period, selected"
                            } else {
                                "${preset.label} period, not selected. Tap to select."
                            }
                        },
                    )
                }
            }
        }

        // Selected range display
        item {
            val fromDisplay = formatDisplayDate(state.fromDate)
            val toDisplay = formatDisplayDate(state.toDate)
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                ),
            ) {
                // a11y: mergeDescendants so TalkBack reads the date range card as one unit.
                Column(
                    modifier = Modifier
                        .padding(12.dp)
                        .semantics(mergeDescendants = true) {
                            contentDescription = "Date range: $fromDisplay to $toDisplay"
                        },
                ) {
                    Text(
                        "Date Range",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        "$fromDisplay – $toDisplay",
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
                            // decorative — non-clickable banner; sibling "Offline – showing cached data" Text carries the announcement
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
                    // a11y: mergeDescendants so TalkBack announces "Loading report" as a single item.
                    Box(
                        modifier = Modifier.semantics(mergeDescendants = true) {
                            contentDescription = "Loading report"
                        },
                    ) {
                        BrandSkeleton(
                            rows = 4,
                            modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                        )
                    }
                }
            }
            state.salesError != null -> {
                item {
                    // a11y: liveRegion=Assertive interrupts TalkBack immediately to announce sales load error.
                    Box(
                        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive },
                    ) {
                        ErrorState(
                            message = state.salesError ?: "Failed to load sales report.",
                            onRetry = onRetry,
                        )
                    }
                }
            }
            else -> {
                val report = state.salesReport
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        val totalRevenueFormatted = com.bizarreelectronics.crm.util.CurrencyFormatter.format(report.totalRevenue)
                        SummaryCard(
                            // @audit-fixed: hand-rolled "$%.2f" replaced with CurrencyFormatter
                            value = totalRevenueFormatted,
                            label = "Total Revenue",
                            // a11y: liveRegion=Polite + contentDescription so TalkBack announces updated KPI value.
                            a11yDescription = "Total Revenue: $totalRevenueFormatted",
                            modifier = Modifier.weight(1f),
                        )
                        SummaryCard(
                            value = "${report.transactionCount}",
                            label = "Transactions",
                            // a11y: liveRegion=Polite + contentDescription so TalkBack announces updated KPI value.
                            a11yDescription = "Transactions: ${report.transactionCount}",
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        val avgFormatted = com.bizarreelectronics.crm.util.CurrencyFormatter.format(report.averageTransaction)
                        SummaryCard(
                            // @audit-fixed: hand-rolled "$%.2f" replaced with CurrencyFormatter
                            value = avgFormatted,
                            label = "Avg Transaction",
                            // a11y: liveRegion=Polite + contentDescription so TalkBack announces updated KPI value.
                            a11yDescription = "Average Transaction: $avgFormatted",
                            modifier = Modifier.weight(1f),
                        )
                        SummaryCard(
                            value = "${report.uniqueCustomers}",
                            label = "Unique Customers",
                            // a11y: liveRegion=Polite + contentDescription so TalkBack announces updated KPI value.
                            a11yDescription = "Unique Customers: ${report.uniqueCustomers}",
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
                if (report.revenueChangePct != null) {
                    item { RevenueChangeCard(changePct = report.revenueChangePct) }
                }
                if (report.paymentMethods.isNotEmpty()) {
                    item {
                        // a11y: heading() so TalkBack navigation-by-heading can jump to Payment Methods section.
                        Text(
                            "Payment Methods",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier
                                .padding(top = 4.dp)
                                .semantics { heading() },
                        )
                    }
                    items(report.paymentMethods, key = { it.method }) { method ->
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
    val changeSign = if (isPositive) "+" else ""
    val changePctFormatted = "$changeSign${String.format(Locale.US, "%.1f", changePct)}%"
    val direction = if (isPositive) "up" else "down"
    Card(
        modifier = Modifier
            .fillMaxWidth()
            // a11y: mergeDescendants + liveRegion=Polite so TalkBack announces when the trend card updates.
            .semantics(mergeDescendants = true) {
                contentDescription = "Revenue vs previous period: $changePctFormatted ($direction)"
                liveRegion = LiveRegionMode.Polite
            },
        colors = CardDefaults.cardColors(containerColor = containerColor),
    ) {
        Row(
            modifier = Modifier.padding(16.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                if (isPositive) Icons.Default.TrendingUp else Icons.Default.TrendingDown,
                // decorative — non-clickable revenue change card; sibling Text siblings carry the announcement
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
                    changePctFormatted,
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
    val revenueFormatted = com.bizarreelectronics.crm.util.CurrencyFormatter.format(method.revenue)
    Card(
        modifier = Modifier
            .fillMaxWidth()
            // a11y: mergeDescendants so TalkBack reads the entire payment method row as one unit.
            .semantics(mergeDescendants = true) {
                contentDescription = "${method.method}: ${method.count} transactions, $revenueFormatted"
            },
    ) {
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
                revenueFormatted,
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
        // a11y: mergeDescendants so TalkBack reads the empty "All clear" state as one unit.
        Box(
            modifier = Modifier
                .fillMaxSize()
                .semantics(mergeDescendants = true) {},
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    Icons.Default.CheckCircle,
                    // decorative — illustrative "all clear" empty-state icon; sibling Text below carries the announcement
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
        modifier = Modifier
            .fillMaxWidth()
            // a11y: mergeDescendants so TalkBack reads the entire attention row as one unit.
            .semantics(mergeDescendants = true) {
                contentDescription = "$label: $count"
                liveRegion = LiveRegionMode.Polite
            },
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
                // decorative — non-clickable attention row; sibling label + count Text carry the announcement
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
    // a11y: optional override for the full TalkBack announcement; defaults to "<label>: <value>".
    a11yDescription: String = "$label: $value",
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
            )
            // a11y: mergeDescendants + liveRegion=Polite so TalkBack announces the card as one unit
            // and re-reads when the value changes (e.g. after a refresh).
            .semantics(mergeDescendants = true) {
                contentDescription = a11yDescription
                liveRegion = LiveRegionMode.Polite
            },
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
