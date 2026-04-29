package com.bizarreelectronics.crm.ui.screens.invoices

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.dto.InvoiceStatsData
import com.bizarreelectronics.crm.data.repository.InvoiceRepository
import com.bizarreelectronics.crm.ui.screens.invoices.components.InvoiceFilterState
import com.bizarreelectronics.crm.ui.screens.invoices.components.InvoiceSort
import com.bizarreelectronics.crm.ui.screens.invoices.components.applyInvoiceSortOrder
import com.bizarreelectronics.crm.util.toDollars
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import javax.inject.Inject

data class InvoiceListUiState(
    val invoices: List<InvoiceEntity> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    // §7.1 — cursor paging
    val isLoadingMore: Boolean = false,
    val hasMore: Boolean = true,
    val error: String? = null,
    val searchQuery: String = "",
    val selectedStatus: String = "All",
    // Sort
    val currentSort: InvoiceSort = InvoiceSort.Newest,
    // Filters
    val activeFilters: InvoiceFilterState = InvoiceFilterState(),
    // Stats — null = not loaded / unavailable
    val stats: InvoiceStatsData? = null,
    // Bulk selection
    val selectedIds: Set<Long> = emptySet(),
    val isBulkMode: Boolean = false,
    // Feedback
    val actionMessage: String? = null,
)

@HiltViewModel
class InvoiceListViewModel @Inject constructor(
    private val invoiceRepository: InvoiceRepository,
    private val invoiceApi: InvoiceApi,
) : ViewModel() {

    private val _state = MutableStateFlow(InvoiceListUiState())
    val state = _state.asStateFlow()

    private var searchJob: Job? = null
    private var collectJob: Job? = null

    // ── §7.1 Cursor paging ────────────────────────────────────────────────────
    private var nextCursor: String? = null
    private var loadMoreJob: Job? = null

    companion object {
        private const val TAG = "InvoiceListVM"
        private const val PAGE_SIZE = 50
    }

    init {
        loadInvoices()
        loadStats()
        loadFirstPage()
    }

    // ── Data loading ─────────────────────────────────────────────────────────

    fun loadInvoices() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            val query = _state.value.searchQuery.trim()
            val statusFilter = _state.value.selectedStatus
            val filters = _state.value.activeFilters
            val sort = _state.value.currentSort

            invoiceRepository.getInvoices()
                .map { invoices ->
                    applyInvoiceSortOrder(
                        applyFilters(invoices, query, statusFilter, filters),
                        sort,
                    )
                }
                .catch { _ ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        error = "Failed to load invoices. Check your connection and try again.",
                    )
                }
                .collectLatest { filtered ->
                    _state.value = _state.value.copy(
                        invoices = filtered,
                        isLoading = false,
                        isRefreshing = false,
                    )
                }
        }
    }

    private fun loadStats() {
        viewModelScope.launch {
            runCatching {
                val resp = invoiceApi.getStats()
                if (resp.success && resp.data != null) {
                    _state.value = _state.value.copy(stats = resp.data)
                }
            }
            // 404 or any other error → leave stats = null (header not shown)
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadInvoices()
        loadStats()
        // Also reset cursor paging so pull-to-refresh refetches page 1.
        loadFirstPage()
    }

    // ── §7.1 Cursor-based paging ──────────────────────────────────────────────

    /**
     * Load the first cursor page. Called on init/refresh. Resets paging state.
     * Results are merged into the Room flow via [InvoiceRepository.loadInvoicesPage]
     * which inserts fetched rows — the existing [collectJob] flow re-emits automatically.
     */
    fun loadFirstPage() {
        loadMoreJob?.cancel()
        nextCursor = null
        _state.value = _state.value.copy(hasMore = true)
        viewModelScope.launch {
            try {
                val filters = buildApiFilters()
                val (_, cursor) = invoiceRepository.loadInvoicesPage(null, PAGE_SIZE, filters)
                nextCursor = cursor
                _state.value = _state.value.copy(hasMore = cursor != null)
            } catch (e: Exception) {
                Log.d(TAG, "loadFirstPage error: ${e.message}")
            }
        }
    }

    /**
     * Append the next cursor page. No-op when already loading, no more pages,
     * or in search mode (search uses its own debounced flow).
     */
    fun loadMore() {
        val s = _state.value
        if (s.isLoadingMore || !s.hasMore || s.isLoading || s.searchQuery.isNotEmpty()) return
        val cursor = nextCursor ?: return
        loadMoreJob?.cancel()
        loadMoreJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoadingMore = true)
            try {
                val filters = buildApiFilters()
                val (_, newCursor) = invoiceRepository.loadInvoicesPage(cursor, PAGE_SIZE, filters)
                nextCursor = newCursor
                _state.value = _state.value.copy(
                    hasMore = newCursor != null,
                    isLoadingMore = false,
                )
            } catch (e: Exception) {
                Log.d(TAG, "loadMore error: ${e.message}")
                _state.value = _state.value.copy(isLoadingMore = false)
            }
        }
    }

    private fun buildApiFilters(): Map<String, String> {
        val filters = _state.value.activeFilters
        return buildMap {
            if (_state.value.selectedStatus != "All") {
                put("status", _state.value.selectedStatus.lowercase())
            }
            if (filters.customerQuery.isNotBlank()) put("customer", filters.customerQuery)
            if (filters.dateFrom.isNotBlank()) put("date_from", filters.dateFrom)
            if (filters.dateTo.isNotBlank()) put("date_to", filters.dateTo)
        }
    }

    // ── Search / filter / sort ────────────────────────────────────────────────

    fun onSearchChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            loadInvoices()
        }
    }

    fun onStatusChanged(status: String) {
        _state.value = _state.value.copy(selectedStatus = status)
        loadInvoices()
        loadFirstPage()
    }

    fun onSortChanged(sort: InvoiceSort) {
        _state.value = _state.value.copy(currentSort = sort)
        loadInvoices()
    }

    fun onFiltersApplied(filters: InvoiceFilterState) {
        _state.value = _state.value.copy(activeFilters = filters)
        loadInvoices()
        loadFirstPage()
    }

    // ── Bulk selection ────────────────────────────────────────────────────────

    fun enterBulkMode(firstId: Long) {
        _state.value = _state.value.copy(
            isBulkMode = true,
            selectedIds = setOf(firstId),
        )
    }

    fun exitBulkMode() {
        _state.value = _state.value.copy(
            isBulkMode = false,
            selectedIds = emptySet(),
        )
    }

    fun toggleSelection(id: Long) {
        val current = _state.value.selectedIds
        _state.value = _state.value.copy(
            selectedIds = if (id in current) current - id else current + id,
        )
    }

    fun selectAll() {
        _state.value = _state.value.copy(
            selectedIds = _state.value.invoices.map { it.id }.toSet(),
        )
    }

    // ── Bulk actions ──────────────────────────────────────────────────────────

    fun bulkSendReminder() {
        val ids = _state.value.selectedIds
        // Stub: real implementation would POST /invoices/bulk-remind with ids.
        _state.value = _state.value.copy(
            actionMessage = "Send reminder: ${ids.size} invoice(s) — not yet implemented on server.",
            isBulkMode = false,
            selectedIds = emptySet(),
        )
    }

    fun bulkDelete() {
        val ids = _state.value.selectedIds
        viewModelScope.launch {
            ids.forEach { id ->
                runCatching { invoiceApi.voidInvoice(id) }
            }
            _state.value = _state.value.copy(
                actionMessage = "Voided ${ids.size} invoice(s).",
                isBulkMode = false,
                selectedIds = emptySet(),
            )
            loadInvoices()
        }
    }

    /** Returns CSV string for the current invoice list. Caller writes to SAF URI. */
    fun buildCsvContent(): String {
        val invoices = _state.value.invoices
        val header = "Invoice #,Customer,Status,Total,Paid,Due,Created"
        val rows = invoices.joinToString("\n") { inv ->
            listOf(
                inv.orderId,
                (inv.customerName ?: "").replace(",", " "),
                inv.status,
                "%.2f".format(inv.total.toDollars()),
                "%.2f".format(inv.amountPaid.toDollars()),
                "%.2f".format(inv.amountDue.toDollars()),
                inv.createdAt.take(10),
            ).joinToString(",")
        }
        return "$header\n$rows"
    }

    // ── Feedback ──────────────────────────────────────────────────────────────

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private fun applyFilters(
        invoices: List<InvoiceEntity>,
        query: String,
        statusFilter: String,
        filters: InvoiceFilterState,
    ): List<InvoiceEntity> {
        var result = invoices

        if (statusFilter != "All") {
            result = result.filter { it.status.equals(statusFilter, ignoreCase = true) }
        }

        if (query.isNotEmpty()) {
            result = result.filter { inv ->
                inv.orderId.contains(query, ignoreCase = true) ||
                    inv.customerName?.contains(query, ignoreCase = true) == true
            }
        }

        if (filters.customerQuery.isNotBlank()) {
            result = result.filter { inv ->
                inv.customerName?.contains(filters.customerQuery, ignoreCase = true) == true
            }
        }

        if (filters.dateFrom.isNotBlank()) {
            result = result.filter { it.createdAt >= filters.dateFrom }
        }
        if (filters.dateTo.isNotBlank()) {
            result = result.filter { it.createdAt.take(10) <= filters.dateTo }
        }

        val minCents = filters.amountMin.toDoubleOrNull()?.let { (it * 100).toLong() }
        val maxCents = filters.amountMax.toDoubleOrNull()?.let { (it * 100).toLong() }
        if (minCents != null) result = result.filter { it.total >= minCents }
        if (maxCents != null) result = result.filter { it.total <= maxCents }

        return result
    }
}
