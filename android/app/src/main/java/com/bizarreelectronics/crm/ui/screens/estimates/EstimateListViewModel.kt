package com.bizarreelectronics.crm.ui.screens.estimates

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.EstimateEntity
import com.bizarreelectronics.crm.data.repository.EstimateRepository
import com.bizarreelectronics.crm.ui.screens.estimates.components.EstimateFilterState
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

data class EstimateListUiState(
    val estimates: List<EstimateEntity> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val searchQuery: String = "",
    val selectedStatus: String = "All",
    // L1321 — filters
    val activeFilters: EstimateFilterState = EstimateFilterState(),
    // L1322 — bulk selection
    val selectedIds: Set<Long> = emptySet(),
    val isBulkMode: Boolean = false,
    // Feedback
    val actionMessage: String? = null,
)

@HiltViewModel
class EstimateListViewModel @Inject constructor(
    private val estimateRepository: EstimateRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(EstimateListUiState())
    val state = _state.asStateFlow()

    private var searchJob: Job? = null
    private var collectJob: Job? = null

    init {
        loadEstimates()
    }

    fun loadEstimates() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = _state.value.estimates.isEmpty(), error = null)
            val query = _state.value.searchQuery.trim()
            val statusFilter = _state.value.selectedStatus
            val filters = _state.value.activeFilters

            val flow = if (query.isNotEmpty()) {
                estimateRepository.searchEstimates(query)
            } else {
                estimateRepository.getEstimates()
            }

            flow
                .map { estimates ->
                    applyFilters(estimates, statusFilter, filters)
                }
                .catch {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        error = "Failed to load estimates. Check your connection and try again.",
                    )
                }
                .collectLatest { estimates ->
                    _state.value = _state.value.copy(
                        estimates = estimates,
                        isLoading = false,
                        isRefreshing = false,
                    )
                }
        }
    }

    private fun applyFilters(
        estimates: List<EstimateEntity>,
        statusFilter: String,
        filters: EstimateFilterState,
    ): List<EstimateEntity> {
        return estimates.filter { e ->
            val statusOk = statusFilter == "All" || e.status.equals(statusFilter, ignoreCase = true)
            val customerOk = filters.customerQuery.isBlank() ||
                e.customerName?.contains(filters.customerQuery, ignoreCase = true) == true
            val dateFromOk = filters.dateFrom.isBlank() || e.createdAt >= filters.dateFrom
            val dateToOk = filters.dateTo.isBlank() || e.createdAt.take(10) <= filters.dateTo
            statusOk && customerOk && dateFromOk && dateToOk
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadEstimates()
    }

    fun onSearchChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            loadEstimates()
        }
    }

    fun onStatusChanged(status: String) {
        _state.value = _state.value.copy(selectedStatus = status)
        loadEstimates()
    }

    // ── L1321 Filters ─────────────────────────────────────────────────────────

    fun onFiltersApplied(filters: EstimateFilterState) {
        _state.value = _state.value.copy(activeFilters = filters)
        loadEstimates()
    }

    // ── L1322 Bulk selection ──────────────────────────────────────────────────

    fun onLongPress(id: Long) {
        val current = _state.value
        val newIds = if (current.selectedIds.contains(id)) {
            current.selectedIds - id
        } else {
            current.selectedIds + id
        }
        _state.value = current.copy(
            selectedIds = newIds,
            isBulkMode = newIds.isNotEmpty(),
        )
    }

    fun toggleSelection(id: Long) {
        onLongPress(id)
    }

    fun selectAll() {
        val allIds = _state.value.estimates.map { it.id }.toSet()
        _state.value = _state.value.copy(selectedIds = allIds, isBulkMode = true)
    }

    fun exitBulkMode() {
        _state.value = _state.value.copy(selectedIds = emptySet(), isBulkMode = false)
    }

    fun bulkSend() {
        val ids = _state.value.selectedIds.toList()
        viewModelScope.launch {
            ids.forEach { id ->
                runCatching { estimateRepository.sendEstimate(id, "sms") }
            }
            _state.value = _state.value.copy(
                selectedIds = emptySet(),
                isBulkMode = false,
                actionMessage = "Sent ${ids.size} estimate(s)",
            )
        }
    }

    fun bulkDelete() {
        val ids = _state.value.selectedIds.toList()
        viewModelScope.launch {
            ids.forEach { id ->
                runCatching { estimateRepository.deleteEstimate(id) }
            }
            _state.value = _state.value.copy(
                selectedIds = emptySet(),
                isBulkMode = false,
                actionMessage = "Deleted ${ids.size} estimate(s)",
            )
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }
}
