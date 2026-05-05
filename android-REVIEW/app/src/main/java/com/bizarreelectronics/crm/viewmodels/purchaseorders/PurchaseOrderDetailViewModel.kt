package com.bizarreelectronics.crm.viewmodels.purchaseorders

import android.util.Log
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderDetailData
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderItem
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderReceiveItemRequest
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderRow
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderUpdateRequest
import com.bizarreelectronics.crm.data.repository.PurchaseOrderRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/** Per-line-item receive qty being entered in the Receive flow. */
data class ReceiveEntry(
    val poItem: PurchaseOrderItem,
    val qtyToReceive: Int,
)

data class PurchaseOrderDetailUiState(
    val isLoading: Boolean = true,
    val error: String? = null,
    val order: PurchaseOrderRow? = null,
    val items: List<PurchaseOrderItem> = emptyList(),
    // Receive flow
    val receiveEntries: List<ReceiveEntry> = emptyList(),
    val isReceiving: Boolean = false,
    val receiveError: String? = null,
    val receiveSuccess: Boolean = false,
    // Cancel confirm dialog
    val showCancelConfirm: Boolean = false,
    val cancelReason: String = "",
    val isCancelling: Boolean = false,
    val cancelError: String? = null,
)

@HiltViewModel
class PurchaseOrderDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repository: PurchaseOrderRepository,
) : ViewModel() {

    private val poId: Long = checkNotNull(savedStateHandle["id"])

    private val _state = MutableStateFlow(PurchaseOrderDetailUiState())
    val state = _state.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val detail = repository.getPurchaseOrder(poId)
                val entries = detail.items.map { item ->
                    ReceiveEntry(
                        poItem = item,
                        qtyToReceive = (item.quantityOrdered - item.quantityReceived).coerceAtLeast(0),
                    )
                }
                _state.value = _state.value.copy(
                    isLoading = false,
                    order = detail.order,
                    items = detail.items,
                    receiveEntries = entries,
                )
            } catch (e: Exception) {
                Log.w(TAG, "load($poId) failed: ${e.message}")
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load purchase order",
                )
            }
        }
    }

    // ── Receive flow ─────────────────────────────────────────────────────────

    fun updateReceiveQty(poItemId: Long, qty: Int) {
        val updated = _state.value.receiveEntries.map { entry ->
            if (entry.poItem.id == poItemId) {
                entry.copy(qtyToReceive = qty.coerceAtLeast(0))
            } else {
                entry
            }
        }
        _state.value = _state.value.copy(receiveEntries = updated)
    }

    /**
     * POST /purchase-orders/:id/receive — sends all non-zero entries.
     * Server increments inventory_items.in_stock atomically.
     */
    fun submitReceive() {
        val entries = _state.value.receiveEntries.filter { it.qtyToReceive > 0 }
        if (entries.isEmpty()) {
            _state.value = _state.value.copy(receiveError = "Enter at least one quantity to receive")
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isReceiving = true, receiveError = null)
            try {
                val items = entries.map { entry ->
                    PurchaseOrderReceiveItemRequest(
                        purchaseOrderItemId = entry.poItem.id,
                        quantityReceived = entry.qtyToReceive,
                    )
                }
                val updated = repository.receivePurchaseOrder(poId, items)
                // Reload detail to reflect new received quantities and PO status
                val detail = repository.getPurchaseOrder(poId)
                val newEntries = detail.items.map { item ->
                    ReceiveEntry(
                        poItem = item,
                        qtyToReceive = (item.quantityOrdered - item.quantityReceived).coerceAtLeast(0),
                    )
                }
                _state.value = _state.value.copy(
                    isReceiving = false,
                    receiveSuccess = true,
                    order = updated,
                    items = detail.items,
                    receiveEntries = newEntries,
                )
            } catch (e: Exception) {
                Log.w(TAG, "submitReceive($poId) failed: ${e.message}")
                _state.value = _state.value.copy(
                    isReceiving = false,
                    receiveError = e.message ?: "Failed to receive items",
                )
            }
        }
    }

    fun clearReceiveSuccess() {
        _state.value = _state.value.copy(receiveSuccess = false, receiveError = null)
    }

    // ── Cancel flow ───────────────────────────────────────────────────────────

    fun requestCancel() {
        _state.value = _state.value.copy(showCancelConfirm = true, cancelReason = "")
    }

    fun onCancelReasonChanged(reason: String) {
        _state.value = _state.value.copy(cancelReason = reason)
    }

    fun dismissCancelConfirm() {
        _state.value = _state.value.copy(showCancelConfirm = false, cancelReason = "", cancelError = null)
    }

    /** Transition PO to 'cancelled' with an optional reason. */
    fun confirmCancel() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isCancelling = true, cancelError = null)
            try {
                val updated = repository.updatePurchaseOrder(
                    id = poId,
                    request = PurchaseOrderUpdateRequest(
                        status = "cancelled",
                        cancelledReason = _state.value.cancelReason.takeIf { it.isNotBlank() },
                    ),
                )
                _state.value = _state.value.copy(
                    isCancelling = false,
                    showCancelConfirm = false,
                    order = updated,
                )
            } catch (e: Exception) {
                Log.w(TAG, "confirmCancel($poId) failed: ${e.message}")
                _state.value = _state.value.copy(
                    isCancelling = false,
                    cancelError = e.message ?: "Failed to cancel purchase order",
                )
            }
        }
    }

    companion object {
        private const val TAG = "PODetailVM"
    }
}
