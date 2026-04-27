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
import androidx.compose.material.icons.outlined.Print
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
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
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import androidx.navigation.compose.rememberNavController
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.remote.api.ReportApi
import com.bizarreelectronics.crm.data.remote.api.ScheduleFrequency
import com.bizarreelectronics.crm.data.remote.api.ScheduledReport
import com.bizarreelectronics.crm.data.remote.api.ScheduledReportSpec
import com.bizarreelectronics.crm.data.repository.DashboardRepository
import com.bizarreelectronics.crm.data.repository.InvoiceRepository
import androidx.compose.foundation.Canvas
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.screens.reports.components.ChartDrillThrough
import com.bizarreelectronics.crm.ui.screens.reports.components.ReportType
import com.bizarreelectronics.crm.ui.screens.reports.components.ReportTypeSelector
import com.bizarreelectronics.crm.ui.screens.reports.components.ReportsExportActions
import com.bizarreelectronics.crm.ui.screens.reports.components.printReport
import com.bizarreelectronics.crm.util.CurrencyFormatter
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

/**
 * A single transaction row displayed in the "Recent Transactions" section of
 * [SalesReportScreen]. Sourced from the local [InvoiceEntity] cache so it is
 * available offline and does not require a dedicated server endpoint.
 */
data class SaleTransaction(
    val orderId: String,
    val invoiceId: Long,
    val customerName: String,
    val totalCents: Long,
    val createdAt: String,
)

/**
 * One row from GET /reports/employees.
 * Fields match server response: name, role, tickets_assigned, tickets_closed,
 * commission_earned (dollars), hours_worked, revenue_generated (dollars).
 */
data class EmployeePerformanceRow(
    val id: Long,
    val name: String,
    val role: String,
    val ticketsAssigned: Int,
    val ticketsClosed: Int,
    val commissionEarned: Double,
    val hoursWorked: Double,
    val revenueGenerated: Double,
)

/** One row from GET /reports/tickets → byTech[]. */
data class TechTicketRow(
    val name: String,
    val ticketCount: Int,
    val closedCount: Int,
    val totalRevenue: Double,
)

/** Parsed response from GET /reports/tickets. */
data class TicketsReport(
    val totalCreated: Int = 0,
    val totalClosed: Int = 0,
    val avgTurnaroundHours: Double? = null,
    val byTech: List<TechTicketRow> = emptyList(),
    /** byDay: ISO-date → created count (for throughput chart). */
    val byDay: List<SalesByDayPoint> = emptyList(),
)

data class LowStockItem(
    val id: Long,
    val name: String,
    val sku: String,
    val inStock: Int,
    val reorderLevel: Int,
)

data class TopMovingItem(
    val name: String,
    val sku: String,
    val usedQty: Int,
    val inStock: Int,
)

data class InventoryValueSummary(
    val itemType: String,
    val itemCount: Int,
    val totalUnits: Int,
    val totalCostValue: Double,
    val totalRetailValue: Double,
)

/**
 * Parsed response from GET /reports/inventory.
 * NOTE §15.5 Shrinkage %: the server endpoint does not track shrinkage
 * (inventory adjustments vs expected movement). Left [ ] until server ships
 * a shrinkage/adjustment column.
 */
data class InventoryReport(
    val lowStock: List<LowStockItem> = emptyList(),
    val valueSummary: List<InventoryValueSummary> = emptyList(),
    val outOfStock: Int = 0,
    val topMoving: List<TopMovingItem> = emptyList(),
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
    // §15 L1722 — SegmentedButton report type
    val selectedReportType: ReportType = ReportType.SALES,
    // §15 L1726 — Scheduled reports
    val scheduledReports: List<ScheduledReport> = emptyList(),
    val isScheduledLoading: Boolean = false,
    // Snackbar messages from schedule actions (null = none pending)
    val scheduleSnackbar: String? = null,
    // Serialized filter spec for drill-through back-stack restoration
    val currentFilterSpec: String = "",
    // Recent transactions list — sourced from local invoice cache for reprint support.
    val recentTransactions: List<SaleTransaction> = emptyList(),
    // §15.4 — employee performance rows
    val employeeRows: List<EmployeePerformanceRow> = emptyList(),
    val isEmployeesLoading: Boolean = false,
    val employeesError: String? = null,
    // §15.7 — busy-hours heatmap (7 rows × 24 cols; null = not yet loaded)
    val busyHoursGrid: List<List<Int>> = emptyList(),
    val busyHoursPeak: Int = 1,
    val isBusyHoursLoading: Boolean = false,
    // §15.3 — tickets report
    val ticketsReport: TicketsReport = TicketsReport(),
    val isTicketsLoading: Boolean = false,
    val ticketsError: String? = null,
    // §15.5 — inventory report
    val inventoryReport: InventoryReport = InventoryReport(),
    val isInventoryLoading: Boolean = false,
    val inventoryError: String? = null,
)

// ─── ViewModel ───────────────────────────────────────────────────────────────

@HiltViewModel
class ReportsViewModel @Inject constructor(
    private val dashboardRepository: DashboardRepository,
    private val reportApi: ReportApi,
    private val serverMonitor: ServerReachabilityMonitor,
    val appPreferences: AppPreferences,
    private val savedStateHandle: SavedStateHandle,
    private val invoiceRepository: InvoiceRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(ReportsUiState())
    val state: StateFlow<ReportsUiState> = _state.asStateFlow()

    init {
        // Restore filter context if returning from a drill-through back-pop
        savedStateHandle.get<String>("filter_spec")?.let { spec ->
            if (spec.isNotEmpty()) restoreFilter(spec)
        }
        loadData()
        loadSalesReport()
        observeOnlineState()
        observeRecentTransactions()
    }

    /** Keeps [ReportsUiState.recentTransactions] in sync with the local invoice DB (top 50). */
    private fun observeRecentTransactions() {
        viewModelScope.launch {
            invoiceRepository.getInvoices().collect { invoices ->
                val transactions = invoices.take(50).map { inv ->
                    SaleTransaction(
                        orderId = inv.orderId,
                        invoiceId = inv.id,
                        customerName = inv.customerName ?: "Unknown",
                        totalCents = inv.total,
                        createdAt = inv.createdAt,
                    )
                }
                _state.update { it.copy(recentTransactions = transactions) }
            }
        }
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

    fun selectReportType(type: ReportType) {
        _state.update { it.copy(selectedReportType = type) }
        when (type) {
            ReportType.SALES -> loadSalesReport()
            ReportType.TICKETS -> loadTicketsReport()
            ReportType.EMPLOYEES -> loadEmployeesReport()
            ReportType.INVENTORY -> loadInventoryReport()
            ReportType.INSIGHTS -> loadBusyHoursHeatmap()
            else -> Unit
        }
    }

    /** Fetches /reports/scheduled — 404 is tolerated and results in an empty list. */
    fun loadScheduledReports() {
        viewModelScope.launch {
            _state.update { it.copy(isScheduledLoading = true) }
            runCatching { reportApi.getScheduledReports() }
                .onSuccess { resp ->
                    val parsed = resp.data?.mapNotNull { item ->
                        val map = item as? Map<*, *> ?: return@mapNotNull null
                        ScheduledReport(
                            id = (map["id"] as? String) ?: return@mapNotNull null,
                            reportType = (map["reportType"] as? String) ?: "",
                            frequency = (map["frequency"] as? String) ?: "DAILY",
                            weekday = (map["weekday"] as? Number)?.toInt(),
                            dayOfMonth = (map["dayOfMonth"] as? Number)?.toInt(),
                            recipients = (map["recipients"] as? String) ?: "",
                            emailEnabled = (map["emailEnabled"] as? Boolean) ?: false,
                            inAppEnabled = (map["inAppEnabled"] as? Boolean) ?: true,
                            fcmEnabled = (map["fcmEnabled"] as? Boolean) ?: false,
                            paused = (map["paused"] as? Boolean) ?: false,
                        )
                    } ?: emptyList()
                    _state.update { it.copy(isScheduledLoading = false, scheduledReports = parsed) }
                }
                .onFailure {
                    // 404 or any error → silently show empty list
                    _state.update { it.copy(isScheduledLoading = false, scheduledReports = emptyList()) }
                }
        }
    }

    /** Create a new scheduled report and reload the list on success. */
    fun createSchedule(spec: ScheduledReportSpec) {
        viewModelScope.launch {
            runCatching { reportApi.createScheduledReport(spec) }
                .onSuccess { loadScheduledReports() }
                .onFailure { e ->
                    _state.update { it.copy(scheduleSnackbar = "Failed to create schedule: ${e.message}") }
                }
        }
    }

    /** Pause an existing schedule. */
    fun pauseSchedule(id: String) {
        viewModelScope.launch {
            runCatching { reportApi.patchScheduledReport(id, mapOf("paused" to true)) }
                .onSuccess { loadScheduledReports() }
                .onFailure { e ->
                    _state.update { it.copy(scheduleSnackbar = "Failed to pause: ${e.message}") }
                }
        }
    }

    /** Resume a paused schedule. */
    fun resumeSchedule(id: String) {
        viewModelScope.launch {
            runCatching { reportApi.patchScheduledReport(id, mapOf("paused" to false)) }
                .onSuccess { loadScheduledReports() }
                .onFailure { e ->
                    _state.update { it.copy(scheduleSnackbar = "Failed to resume: ${e.message}") }
                }
        }
    }

    /** Delete a scheduled report by id. */
    fun deleteSchedule(id: String) {
        viewModelScope.launch {
            runCatching { reportApi.deleteScheduledReport(id) }
                .onSuccess { loadScheduledReports() }
                .onFailure { e ->
                    _state.update { it.copy(scheduleSnackbar = "Failed to delete: ${e.message}") }
                }
        }
    }

    /** Clears the snackbar message after it has been shown. */
    fun clearScheduleSnackbar() {
        _state.update { it.copy(scheduleSnackbar = null) }
    }

    // ── §15 L1730 — Filter-preservation for drill-through back-stack ──────────

    /**
     * Serializes the current date-range filter into [SavedStateHandle] before
     * navigating into a drill-through destination. On back-pop the Compose
     * NavHost restores this entry's ViewModel (same instance for the same
     * back-stack entry); the [init] block will re-apply the filter so the
     * user returns to the same filtered view.
     *
     * Format: "preset|fromMillis|toMillis" — intentionally simple, no JSON dep.
     */
    fun rememberFilterForDrill() {
        val s = _state.value
        val spec = "${s.selectedPreset.name}|${s.fromDate}|${s.toDate}"
        savedStateHandle["filter_spec"] = spec
        _state.update { it.copy(currentFilterSpec = spec) }
    }

    private fun restoreFilter(spec: String) {
        val parts = spec.split("|")
        if (parts.size != 3) return
        val preset = runCatching { DateRangePreset.valueOf(parts[0]) }.getOrNull() ?: return
        val from = parts[1].toLongOrNull() ?: return
        val to = parts[2].toLongOrNull() ?: return
        _state.update {
            it.copy(
                selectedPreset = preset,
                fromDate = from,
                toDate = to,
                currentFilterSpec = spec,
            )
        }
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

    // ── §15.3 — tickets report ────────────────────────────────────────────────

    fun loadTicketsReport() {
        viewModelScope.launch {
            _state.update { it.copy(isTicketsLoading = true, ticketsError = null) }
            runCatching {
                reportApi.getTicketsReport(
                    mapOf(
                        "from_date" to formatServerDate(_state.value.fromDate),
                        "to_date"   to formatServerDate(_state.value.toDate),
                    )
                )
            }.onSuccess { resp ->
                val data = resp.data ?: run {
                    _state.update { it.copy(isTicketsLoading = false) }
                    return@onSuccess
                }
                val summary = data["summary"] as? Map<*, *>
                val byTech = (data["byTech"] as? List<*>)?.mapNotNull { row ->
                    val m = row as? Map<*, *> ?: return@mapNotNull null
                    TechTicketRow(
                        name         = (m["tech_name"] as? String) ?: "Unknown",
                        ticketCount  = (m["ticket_count"] as? Number)?.toInt() ?: 0,
                        closedCount  = (m["closed_count"] as? Number)?.toInt() ?: 0,
                        totalRevenue = (m["total_revenue"] as? Number)?.toDouble() ?: 0.0,
                    )
                } ?: emptyList()
                val byDay = (data["byDay"] as? List<*>)?.mapNotNull { row ->
                    val m = row as? Map<*, *> ?: return@mapNotNull null
                    val day = (m["day"] as? String) ?: return@mapNotNull null
                    val count = (m["created"] as? Number)?.toLong() ?: 0L
                    SalesByDayPoint(isoDate = day, totalCents = count) // reuses point type; cents = ticket count
                } ?: emptyList()
                _state.update {
                    it.copy(
                        isTicketsLoading = false,
                        ticketsReport = TicketsReport(
                            totalCreated       = (summary?.get("total_created") as? Number)?.toInt() ?: 0,
                            totalClosed        = (summary?.get("total_closed") as? Number)?.toInt() ?: 0,
                            avgTurnaroundHours = (summary?.get("avg_turnaround_hours") as? Number)?.toDouble(),
                            byTech             = byTech,
                            byDay              = byDay,
                        ),
                    )
                }
            }.onFailure { e ->
                _state.update {
                    it.copy(
                        isTicketsLoading = false,
                        ticketsError = e.message ?: "Failed to load tickets report",
                    )
                }
            }
        }
    }

    // ── §15.4 — employee performance ─────────────────────────────────────────

    fun loadEmployeesReport() {
        viewModelScope.launch {
            _state.update { it.copy(isEmployeesLoading = true, employeesError = null) }
            runCatching {
                reportApi.getEmployeesReport(
                    mapOf(
                        "from_date" to formatServerDate(_state.value.fromDate),
                        "to_date"   to formatServerDate(_state.value.toDate),
                    )
                )
            }.onSuccess { resp ->
                val rows = (resp.data?.get("rows") as? List<*>)?.mapNotNull { item ->
                    val m = item as? Map<*, *> ?: return@mapNotNull null
                    EmployeePerformanceRow(
                        id               = (m["id"] as? Number)?.toLong() ?: 0L,
                        name             = (m["name"] as? String) ?: "Unknown",
                        role             = (m["role"] as? String) ?: "",
                        ticketsAssigned  = (m["tickets_assigned"] as? Number)?.toInt() ?: 0,
                        ticketsClosed    = (m["tickets_closed"] as? Number)?.toInt() ?: 0,
                        commissionEarned = (m["commission_earned"] as? Number)?.toDouble() ?: 0.0,
                        hoursWorked      = (m["hours_worked"] as? Number)?.toDouble() ?: 0.0,
                        revenueGenerated = (m["revenue_generated"] as? Number)?.toDouble() ?: 0.0,
                    )
                } ?: emptyList()
                _state.update { it.copy(isEmployeesLoading = false, employeeRows = rows) }
            }.onFailure { e ->
                _state.update {
                    it.copy(
                        isEmployeesLoading = false,
                        employeesError = e.message ?: "Failed to load employee report",
                    )
                }
            }
        }
    }

    // ── §15.5 — inventory report ──────────────────────────────────────────────

    fun loadInventoryReport() {
        viewModelScope.launch {
            _state.update { it.copy(isInventoryLoading = true, inventoryError = null) }
            runCatching { reportApi.getInventoryReport() }
                .onSuccess { resp ->
                    val data = resp.data ?: run {
                        _state.update { it.copy(isInventoryLoading = false) }
                        return@onSuccess
                    }
                    val lowStock = (data["lowStock"] as? List<*>)?.mapNotNull { item ->
                        val m = item as? Map<*, *> ?: return@mapNotNull null
                        LowStockItem(
                            id           = (m["id"] as? Number)?.toLong() ?: 0L,
                            name         = (m["name"] as? String) ?: "",
                            sku          = (m["sku"] as? String) ?: "",
                            inStock      = (m["in_stock"] as? Number)?.toInt() ?: 0,
                            reorderLevel = (m["reorder_level"] as? Number)?.toInt() ?: 0,
                        )
                    } ?: emptyList()
                    val valueSummary = (data["valueSummary"] as? List<*>)?.mapNotNull { item ->
                        val m = item as? Map<*, *> ?: return@mapNotNull null
                        InventoryValueSummary(
                            itemType         = (m["item_type"] as? String) ?: "",
                            itemCount        = (m["item_count"] as? Number)?.toInt() ?: 0,
                            totalUnits       = (m["total_units"] as? Number)?.toInt() ?: 0,
                            totalCostValue   = (m["total_cost_value"] as? Number)?.toDouble() ?: 0.0,
                            totalRetailValue = (m["total_retail_value"] as? Number)?.toDouble() ?: 0.0,
                        )
                    } ?: emptyList()
                    val topMoving = (data["topMoving"] as? List<*>)?.mapNotNull { item ->
                        val m = item as? Map<*, *> ?: return@mapNotNull null
                        TopMovingItem(
                            name    = (m["name"] as? String) ?: "",
                            sku     = (m["sku"] as? String) ?: "",
                            usedQty = (m["used_qty"] as? Number)?.toInt() ?: 0,
                            inStock = (m["in_stock"] as? Number)?.toInt() ?: 0,
                        )
                    } ?: emptyList()
                    val outOfStock = (data["outOfStock"] as? Number)?.toInt() ?: 0
                    _state.update {
                        it.copy(
                            isInventoryLoading = false,
                            inventoryReport = InventoryReport(
                                lowStock     = lowStock,
                                valueSummary = valueSummary,
                                outOfStock   = outOfStock,
                                topMoving    = topMoving,
                            ),
                        )
                    }
                }
                .onFailure { e ->
                    _state.update {
                        it.copy(
                            isInventoryLoading = false,
                            inventoryError = e.message ?: "Failed to load inventory report",
                        )
                    }
                }
        }
    }

    // ── §15.7 — busy-hours heatmap ────────────────────────────────────────────

    fun loadBusyHoursHeatmap() {
        viewModelScope.launch {
            _state.update { it.copy(isBusyHoursLoading = true) }
            runCatching { reportApi.getBusyHoursHeatmap() }
                .onSuccess { resp ->
                    // grid is a JSON array of arrays: [[Int,…]×24]×7
                    val rawGrid = resp.data?.get("grid") as? List<*>
                    val grid: List<List<Int>> = rawGrid?.mapNotNull { row ->
                        (row as? List<*>)?.mapNotNull { cell ->
                            (cell as? Number)?.toInt()
                        }?.takeIf { it.size == 24 }
                    } ?: emptyList()
                    val peak = ((resp.data?.get("peak") as? Number)?.toInt() ?: 1).coerceAtLeast(1)
                    _state.update {
                        it.copy(
                            isBusyHoursLoading = false,
                            busyHoursGrid = grid,
                            busyHoursPeak = peak,
                        )
                    }
                }
                .onFailure {
                    _state.update { it.copy(isBusyHoursLoading = false) }
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
    navController: NavController = rememberNavController(),
    viewModel: ReportsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    var selectedTabIndex by remember { mutableIntStateOf(0) }
    // "Overview" tab (index 1) hosts the §15 Vico charts.
    // Existing indices shifted: Dashboard=0, Overview=1, Sales=2, Needs Attention=3.
    val tabs = listOf("Dashboard", "Overview", "Sales", "Needs Attention")
    var showScheduleSheet by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Reports",
                actions = {
                    // Print button — only shown on the inline SALES type (inline tabs).
                    // Sub-report screens (Tax, Inventory, etc.) have their own top-bar actions.
                    if (state.selectedReportType == ReportType.SALES) {
                        IconButton(
                            onClick = {
                                printReport(
                                    context = context,
                                    reportTitle = "Sales_Report",
                                    html = buildInlineSalesHtml(state),
                                )
                            },
                        ) {
                            Icon(Icons.Outlined.Print, contentDescription = "Print report")
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            // ── §15 L1722 SegmentedButton report-type selector ─────────────
            ReportTypeSelector(
                selected = state.selectedReportType,
                onSelect = { type ->
                    viewModel.selectReportType(type)
                    // Navigate to sub-report screens for non-inline types
                    when (type) {
                        ReportType.SALES -> { /* rendered inline via tabs */ }
                        else -> { /* sub-screens rendered below via when() */ }
                    }
                },
            )

            // CROSS37: TabRow labels all rendered in primary color; only the
            // underline indicated the active tab. Conditionally color the label
            // text via the `selected` prop so active=primary and
            // inactive=onSurfaceVariant — underline (already primary) + text
            // color both carry the active-state signal.
            if (state.selectedReportType == ReportType.SALES) {
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
            }

            PullToRefreshBox(
                isRefreshing = state.isRefreshing,
                onRefresh = { viewModel.refresh() },
                modifier = Modifier.fillMaxSize(),
            ) {
                when (state.selectedReportType) {
                    ReportType.SALES -> SalesTabContent(
                        state = state,
                        selectedTabIndex = selectedTabIndex,
                        viewModel = viewModel,
                        onDrillThroughDate = { date ->
                            viewModel.rememberFilterForDrill()
                            navController.navigate("tickets?date=$date")
                        },
                    )
                    ReportType.TICKETS -> TicketsReportScreen(viewModel = viewModel)
                    ReportType.EMPLOYEES -> EmployeesReportScreen(state = state, viewModel = viewModel)
                    ReportType.INVENTORY -> InventoryReportScreen(viewModel = viewModel)
                    ReportType.TAX -> TaxReportScreen(viewModel = viewModel)
                    ReportType.INSIGHTS -> InsightsScreen(state = state, viewModel = viewModel)
                    ReportType.CUSTOM -> CustomReportScreen()
                }
            }
        }
    }

    // §15 L1758 — Schedule bottom sheet
    if (showScheduleSheet) {
        ScheduleReportSheet(
            viewModel = viewModel,
            onDismiss = { showScheduleSheet = false },
        )
    }

    // Snackbar for schedule action errors
    val snackbarHostState = remember { SnackbarHostState() }
    val scheduleSnackbar = state.scheduleSnackbar
    LaunchedEffect(scheduleSnackbar) {
        if (scheduleSnackbar != null) {
            snackbarHostState.showSnackbar(scheduleSnackbar)
            viewModel.clearScheduleSnackbar()
        }
    }
}

// ─── Tab content for SALES type ───────────────────────────────────────────────

@Composable
private fun SalesTabContent(
    state: ReportsUiState,
    selectedTabIndex: Int,
    viewModel: ReportsViewModel,
    onDrillThroughDate: (String) -> Unit,
) {
    val isSalesTab = selectedTabIndex == 2
    if (state.isLoading && !state.isRefreshing && !isSalesTab) {
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
                onDrillThroughDate = onDrillThroughDate,
            )
            2 -> SalesReportScreenInline(
                state = state,
                viewModel = viewModel,
                onDrillThroughDate = onDrillThroughDate,
            )
            3 -> NeedsAttentionTab(state)
        }
    }
}

/**
 * Inline Sales report content (used inside the existing TabRow at index 2).
 * Full-page variant is [SalesReportScreen] (separate file for standalone navigation).
 */
@Composable
private fun SalesReportScreenInline(
    state: ReportsUiState,
    viewModel: ReportsViewModel,
    onDrillThroughDate: (String) -> Unit,
) {
    SalesReportTab(
        state = state,
        onPresetSelected = viewModel::selectPreset,
        onCustomRangeSelected = viewModel::setCustomRange,
        onRetry = viewModel::loadSalesReport,
    )
}

// ─── Placeholder sub-report screens ──────────────────────────────────────────

/**
 * Employee performance report (ActionPlan §15.4).
 *
 * Wired to GET /reports/employees. Shows a leaderboard table with:
 *   - Name / role
 *   - Tickets assigned vs closed
 *   - Hours worked (from clock_entries)
 *   - Revenue generated (payments attributed to this user)
 *   - Commission earned
 *
 * Data is loaded on demand when the EMPLOYEES segment is selected.
 * NOTE §15.4: "Label breakdowns" (15.3) — no /reports/tickets?labels server endpoint;
 * ticket_labels are not yet aggregated in the reports route.  Left [ ] until server ships.
 */
@Composable
private fun EmployeesReportScreen(
    state: ReportsUiState,
    viewModel: ReportsViewModel,
) {
    LaunchedEffect(Unit) {
        if (state.employeeRows.isEmpty() && !state.isEmployeesLoading) {
            viewModel.loadEmployeesReport()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Employee Performance",
                actions = {
                    ReportsExportActions(
                        reportTitle = "Employee_Performance",
                        csvContent = { buildEmployeesCsv(state.employeeRows) },
                    )
                },
            )
        },
    ) { padding ->
        when {
            state.isEmployeesLoading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
            state.employeesError != null -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.employeesError,
                        onRetry = { viewModel.loadEmployeesReport() },
                    )
                }
            }
            state.employeeRows.isEmpty() -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "No employee data for this period.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(32.dp),
                    )
                }
            }
            else -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    item {
                        Text(
                            "Leaderboard",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.semantics { heading() },
                        )
                    }
                    items(state.employeeRows, key = { it.id }) { row ->
                        EmployeePerformanceCard(row = row)
                    }
                }
            }
        }
    }
}

@Composable
private fun EmployeePerformanceCard(row: EmployeePerformanceRow) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = buildString {
                    append("${row.name}, ${row.role}. ")
                    append("${row.ticketsClosed} of ${row.ticketsAssigned} tickets closed. ")
                    append("Hours worked: ${"%.1f".format(row.hoursWorked)}. ")
                    append("Revenue: ${CurrencyFormatter.format(row.revenueGenerated)}. ")
                    append("Commission: ${CurrencyFormatter.format(row.commissionEarned)}.")
                }
            },
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(row.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                    Text(
                        row.role.replaceFirstChar { it.uppercase() },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    CurrencyFormatter.format(row.revenueGenerated),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            Spacer(Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                EmployeeStatChip(label = "Tickets", value = "${row.ticketsClosed}/${row.ticketsAssigned}")
                EmployeeStatChip(label = "Hours", value = "${"%.1f".format(row.hoursWorked)} h")
                EmployeeStatChip(label = "Commission", value = CurrencyFormatter.format(row.commissionEarned))
            }
        }
    }
}

@Composable
private fun EmployeeStatChip(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            value,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun buildEmployeesCsv(rows: List<EmployeePerformanceRow>): String = buildString {
    appendLine("Name,Role,Tickets Assigned,Tickets Closed,Hours Worked,Revenue Generated,Commission Earned")
    rows.forEach { r ->
        appendLine("${r.name},${r.role},${r.ticketsAssigned},${r.ticketsClosed},${"%.2f".format(r.hoursWorked)},${"%.2f".format(r.revenueGenerated)},${"%.2f".format(r.commissionEarned)}")
    }
}

/**
 * Insights screen (ActionPlan §15.7).
 *
 * Wired to GET /reports/busy-hours-heatmap.  Renders a 7×24 ticket-volume
 * heatmap (Canvas-drawn grid) where cell opacity scales linearly from 0 to
 * peak.  Tapping a cell fires [onDrillThroughDow] → filters tickets to that
 * day-of-week (formatted as "dow=N" query param).
 *
 * BI widget cards (Profit Hero, Churn, Forecast) continue to point to the
 * Dashboard where those widgets already live (shipped in commit 12a8756).
 */
@Composable
private fun InsightsScreen(
    state: ReportsUiState,
    viewModel: ReportsViewModel,
) {
    LaunchedEffect(Unit) {
        if (state.busyHoursGrid.isEmpty() && !state.isBusyHoursLoading) {
            viewModel.loadBusyHoursHeatmap()
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Heatmap card
        item {
            ChartSection(title = "Busy Hours Heatmap") {
                when {
                    state.isBusyHoursLoading -> {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(160.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            CircularProgressIndicator()
                        }
                    }
                    state.busyHoursGrid.isEmpty() -> {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(160.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                "No ticket data available.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                textAlign = TextAlign.Center,
                            )
                        }
                    }
                    else -> {
                        BusyHoursHeatmap(
                            grid = state.busyHoursGrid,
                            peak = state.busyHoursPeak,
                        )
                    }
                }
            }
        }

        // BI pointer card — dashboard widgets already live there
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(
                        Icons.Default.Insights,
                        contentDescription = null,
                        modifier = Modifier.size(32.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Column {
                        Text(
                            "AI Business Insights",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            "Profit Hero, Churn, Forecast, and Missing Parts cards live on the Dashboard.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

/**
 * Canvas-drawn busy-hours heatmap.
 *
 * grid[dow][hour] — dow 0=Sun, hour 0–23.  Cell color is the theme primary
 * blended from 0% to 100% alpha against the surface color proportionally to
 * value / peak.  Row labels (Sun–Sat) are drawn on the left; hour ticks are
 * drawn along the top (every 6 hours: 0, 6, 12, 18).
 *
 * TalkBack: a single contentDescription summarises the peak dow and hour.
 */
@Composable
private fun BusyHoursHeatmap(
    grid: List<List<Int>>,
    peak: Int,
    modifier: Modifier = Modifier,
) {
    val dayLabels = listOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
    val primary = MaterialTheme.colorScheme.primary

    // Find busiest (dow, hour) for a11y
    var peakDow = 0; var peakHour = 0
    for (d in grid.indices) {
        for (h in grid[d].indices) {
            if (grid[d][h] > (grid.getOrNull(peakDow)?.getOrNull(peakHour) ?: 0)) {
                peakDow = d; peakHour = h
            }
        }
    }
    val a11yDesc = if (grid.isNotEmpty()) {
        "Busy hours heatmap. Busiest: ${dayLabels.getOrElse(peakDow) { "?" }} at ${peakHour}:00."
    } else "No data"

    Column(
        modifier = modifier
            .fillMaxWidth()
            .semantics { contentDescription = a11yDesc },
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        // Hour header (0, 6, 12, 18, 23)
        Row(modifier = Modifier.fillMaxWidth().padding(start = 36.dp)) {
            listOf(0, 6, 12, 18).forEach { h ->
                Text(
                    "$h",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(6f),
                )
            }
            // filler for last 5 columns (19–23)
            Spacer(modifier = Modifier.weight(4f))
        }

        for (dow in 0 until 7) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Day label
                Text(
                    dayLabels.getOrElse(dow) { "" },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.width(32.dp),
                )
                // 24 cells
                Row(
                    modifier = Modifier
                        .weight(1f)
                        .height(20.dp),
                    horizontalArrangement = Arrangement.spacedBy(1.dp),
                ) {
                    for (hour in 0 until 24) {
                        val value = grid.getOrNull(dow)?.getOrNull(hour) ?: 0
                        val alpha = if (peak > 0) value.toFloat() / peak.toFloat() else 0f
                        val cellColor = primary.copy(alpha = alpha.coerceIn(0.05f, 1f))
                        Canvas(modifier = Modifier.weight(1f).fillMaxHeight()) {
                            drawRect(color = cellColor)
                        }
                    }
                }
            }
        }
    }
}

// ─── §15 L1758 — Schedule report bottom sheet ────────────────────────────────

private val WEEKDAY_LABELS = listOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleReportSheet(
    viewModel: ReportsViewModel,
    onDismiss: () -> Unit,
) {
    val state by viewModel.state.collectAsState()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var selectedFrequency by rememberSaveable { mutableStateOf(ScheduleFrequency.WEEKLY) }
    var selectedWeekday by rememberSaveable { mutableIntStateOf(1) }
    var selectedDayOfMonth by rememberSaveable { mutableIntStateOf(1) }
    var emailEnabled by rememberSaveable { mutableStateOf(false) }
    var inAppEnabled by rememberSaveable { mutableStateOf(true) }
    var fcmEnabled by rememberSaveable { mutableStateOf(false) }
    var recipients by rememberSaveable { mutableStateOf("") }
    var showDeleteConfirm by rememberSaveable { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) { viewModel.loadScheduledReports() }

    showDeleteConfirm?.let { scheduleId ->
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = null },
            title = { Text("Delete schedule?") },
            text = { Text("This scheduled report will be permanently removed.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteSchedule(scheduleId)
                    showDeleteConfirm = null
                }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = null }) { Text("Cancel") }
            },
        )
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            contentPadding = PaddingValues(bottom = 32.dp, top = 8.dp),
        ) {
            item {
                Text(
                    "Schedule Report",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            // Frequency
            item {
                Text("Frequency", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                ScheduleFrequency.values().forEach { freq ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(freq.name.lowercase().replaceFirstChar { it.uppercase() }, style = MaterialTheme.typography.bodyMedium)
                        RadioButton(selected = selectedFrequency == freq, onClick = { selectedFrequency = freq })
                    }
                }
            }

            // Weekday picker
            if (selectedFrequency == ScheduleFrequency.WEEKLY) {
                item {
                    Text("Day of week", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(4.dp))
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(WEEKDAY_LABELS.size) { i ->
                            FilterChip(
                                selected = selectedWeekday == i,
                                onClick = { selectedWeekday = i },
                                label = { Text(WEEKDAY_LABELS[i]) },
                            )
                        }
                    }
                }
            }

            // Day-of-month picker
            if (selectedFrequency == ScheduleFrequency.MONTHLY) {
                item {
                    Text("Day of month (1–28)", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(4.dp))
                    OutlinedTextField(
                        value = if (selectedDayOfMonth > 0) selectedDayOfMonth.toString() else "",
                        onValueChange = { v ->
                            val n = v.filter { it.isDigit() }.toIntOrNull() ?: 1
                            selectedDayOfMonth = n.coerceIn(1, 28)
                        },
                        singleLine = true,
                        label = { Text("Day") },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                            keyboardType = androidx.compose.ui.text.input.KeyboardType.Number,
                        ),
                    )
                }
            }

            // Delivery channels
            item {
                Text("Delivery channels", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Email recipients", style = MaterialTheme.typography.bodyMedium)
                    Checkbox(checked = emailEnabled, onCheckedChange = { emailEnabled = it })
                }
                if (emailEnabled) {
                    OutlinedTextField(
                        value = recipients,
                        onValueChange = { recipients = it },
                        label = { Text("Emails (comma-separated)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                            keyboardType = androidx.compose.ui.text.input.KeyboardType.Email,
                        ),
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("In-app notification", style = MaterialTheme.typography.bodyMedium)
                    Checkbox(checked = inAppEnabled, onCheckedChange = { inAppEnabled = it })
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("FCM push notification", style = MaterialTheme.typography.bodyMedium)
                    Checkbox(checked = fcmEnabled, onCheckedChange = { fcmEnabled = it })
                }
            }

            // Create button
            item {
                Button(
                    onClick = {
                        viewModel.createSchedule(
                            ScheduledReportSpec(
                                reportType = "sales",
                                frequency = selectedFrequency,
                                weekday = selectedWeekday,
                                dayOfMonth = selectedDayOfMonth,
                                recipients = recipients,
                                emailEnabled = emailEnabled,
                                inAppEnabled = inAppEnabled,
                                fcmEnabled = fcmEnabled,
                            )
                        )
                        onDismiss()
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = emailEnabled || inAppEnabled || fcmEnabled,
                ) {
                    Text("Add Schedule")
                }
            }

            // Existing schedules list
            if (state.isScheduledLoading) {
                item {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp))
                    }
                }
            } else if (state.scheduledReports.isNotEmpty()) {
                item {
                    HorizontalDivider()
                    Spacer(Modifier.height(4.dp))
                    Text("Existing schedules", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                items(state.scheduledReports.size) { i ->
                    val schedule = state.scheduledReports[i]
                    ScheduleRow(
                        schedule = schedule,
                        onPause = { viewModel.pauseSchedule(schedule.id) },
                        onResume = { viewModel.resumeSchedule(schedule.id) },
                        onDelete = { showDeleteConfirm = schedule.id },
                    )
                }
            }
        }
    }
}

@Composable
private fun ScheduleRow(
    schedule: ScheduledReport,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onDelete: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (schedule.paused) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    schedule.reportType.replaceFirstChar { it.uppercase() },
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    buildString {
                        append(schedule.frequency.lowercase().replaceFirstChar { it.uppercase() })
                        if (schedule.paused) append(" · Paused")
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = if (schedule.paused) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (schedule.paused) {
                IconButton(onClick = onResume) {
                    Icon(Icons.Default.PlayArrow, contentDescription = "Resume schedule", tint = MaterialTheme.colorScheme.primary)
                }
            } else {
                IconButton(onClick = onPause) {
                    Icon(Icons.Default.Pause, contentDescription = "Pause schedule", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            IconButton(onClick = onDelete) {
                Icon(Icons.Default.Delete, contentDescription = "Delete schedule", tint = MaterialTheme.colorScheme.error)
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
    onDrillThroughDate: (String) -> Unit = {},
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
                ChartDrillThrough(
                    dateLabels = state.salesByDay.map { it.isoDate },
                    onDrillThrough = onDrillThroughDate,
                ) {
                    SalesByDayBarChart(
                        points = state.salesByDay,
                        appPreferences = appPreferences,
                    )
                }
            }
        }
        item {
            // a11y: heading() on the section title column so TalkBack users can jump between chart sections.
            ChartSection(title = "Revenue Over Time") {
                ChartDrillThrough(
                    dateLabels = state.revenueOverTime.map { it.isoDate },
                    onDrillThrough = onDrillThroughDate,
                ) {
                    RevenueOverTimeLineChart(
                        points = state.revenueOverTime,
                        appPreferences = appPreferences,
                    )
                }
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

// ─── Print helpers ────────────────────────────────────────────────────────────

/**
 * Builds a minimal print-friendly HTML snapshot of the inline Sales report.
 * Used by the Print IconButton in [ReportsScreen]'s top bar.
 */
private fun buildInlineSalesHtml(state: ReportsUiState): String = buildString {
    val report = state.salesReport
    val from = formatDisplayDate(state.fromDate)
    val to = formatDisplayDate(state.toDate)
    append("""
        <html><head><meta charset="utf-8">
        <style>
          body{font-family:sans-serif;margin:24px;color:#1a1a1a}
          h1{font-size:20px;margin-bottom:4px}
          p.period{font-size:13px;color:#666;margin:0 0 16px}
          table{width:100%;border-collapse:collapse;font-size:14px}
          th{background:#2c2c2c;color:#fff;text-align:left;padding:8px 12px}
          td{padding:8px 12px;border-bottom:1px solid #e0e0e0}
          td.num{text-align:right}
        </style></head><body>
        <h1>Sales Report — Bizarre Electronics</h1>
        <p class="period">$from – $to</p>
        <table>
          <thead><tr><th>Metric</th><th>Value</th></tr></thead>
          <tbody>
            <tr><td>Total Revenue</td><td class="num">${com.bizarreelectronics.crm.util.CurrencyFormatter.format(report.totalRevenue)}</td></tr>
            <tr><td>Transactions</td><td class="num">${report.transactionCount}</td></tr>
            <tr><td>Avg Transaction</td><td class="num">${com.bizarreelectronics.crm.util.CurrencyFormatter.format(report.averageTransaction)}</td></tr>
            <tr><td>Unique Customers</td><td class="num">${report.uniqueCustomers}</td></tr>
          </tbody>
        </table>
        </body></html>
    """.trimIndent())
}
