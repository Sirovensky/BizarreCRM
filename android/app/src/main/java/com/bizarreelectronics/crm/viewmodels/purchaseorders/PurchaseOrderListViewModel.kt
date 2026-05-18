package com.bizarreelectronics.crm.viewmodels.purchaseorders

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.dto.Pagination
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderRow
import com.bizarreelectronics.crm.data.repository.PurchaseOrderRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class PurchaseOrderListUiState(
    val orders: List<PurchaseOrderRow> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val statusFilter: String? = null,  // null = all
    val pagination: Pagination? = null,
)

/** Status options for the filter chip row. */
val PO_STATUS_OPTIONS = listOf("all", "draft", "pending", "ordered", "partial", "backordered", "received", "cancelled")

@HiltViewModel
class PurchaseOrderListViewModel @Inject constructor(
    private val repository: PurchaseOrderRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(PurchaseOrderListUiState())
    val state = _state.asStateFlow()

    /**
     * BUGHUNT-2026-05-17: tracks the in-flight load so a rapid filter change
     * cancels the previous fetch. Without this, two `viewModelScope.launch`
     * blocks ran concurrently and whichever finished last clobbered state —
     * a slow "draft" fetch landing after a fast "received" fetch showed
     * "draft" rows under the "received" tab.
     */
    private var loadJob: Job? = null

    init {
        load()
    }

    fun load() {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val data = repository.listPurchaseOrders(
                    status = _state.value.statusFilter,
                )
                _state.value = _state.value.copy(
                    orders = data.orders,
                    pagination = data.pagination,
                    isLoading = false,
                    isRefreshing = false,
                )
            } catch (e: CancellationException) {
                // Don't paint "cancelled" over the now-current load; re-throw
                // so the structured-concurrency contract is preserved.
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "load failed: ${e.message}")
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    error = e.message ?: "Failed to load purchase orders",
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        load()
    }

    fun onStatusFilterChanged(status: String?) {
        _state.value = _state.value.copy(statusFilter = if (status == "all") null else status)
        load()
    }

    companion object {
        private const val TAG = "POListVM"
    }
}
