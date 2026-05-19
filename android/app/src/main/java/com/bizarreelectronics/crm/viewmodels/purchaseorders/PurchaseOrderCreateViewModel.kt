package com.bizarreelectronics.crm.viewmodels.purchaseorders

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderCreateRequest
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderItemRequest
import com.bizarreelectronics.crm.data.remote.dto.SupplierRow
import com.bizarreelectronics.crm.data.repository.PurchaseOrderRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/** A draft line item being built in the Create PO form. */
data class DraftPoItem(
    val inventoryItemId: Long,
    val itemName: String,
    val sku: String?,
    val quantityOrdered: Int = 1,
    val costPrice: Double = 0.0,
)

data class PurchaseOrderCreateUiState(
    // Form fields
    val selectedSupplierId: Long? = null,
    val selectedSupplierName: String? = null,
    val notes: String = "",
    val expectedDate: String = "",
    val lineItems: List<DraftPoItem> = emptyList(),
    // Supplier picker data
    val suppliers: List<SupplierRow> = emptyList(),
    val suppliersLoading: Boolean = false,
    // Submit state
    val isSubmitting: Boolean = false,
    val submitError: String? = null,
    val createdPoId: Long? = null,  // non-null = navigate away
)

@HiltViewModel
class PurchaseOrderCreateViewModel @Inject constructor(
    private val repository: PurchaseOrderRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(PurchaseOrderCreateUiState())
    val state = _state.asStateFlow()

    init {
        loadSuppliers()
    }

    private fun loadSuppliers() {
        viewModelScope.launch {
            _state.update { it.copy(suppliersLoading = true) }
            val suppliers = repository.listSuppliers()
            _state.update { it.copy(suppliers = suppliers, suppliersLoading = false) }
        }
    }

    fun onSupplierSelected(supplierId: Long, supplierName: String) {
        _state.update {
            it.copy(
                selectedSupplierId = supplierId,
                selectedSupplierName = supplierName,
            )
        }
    }

    fun onNotesChanged(notes: String) {
        _state.update { it.copy(notes = notes) }
    }

    fun onExpectedDateChanged(date: String) {
        _state.update { it.copy(expectedDate = date) }
    }

    fun addLineItem(item: DraftPoItem) {
        _state.update { it.copy(lineItems = _state.value.lineItems + item) }
    }

    fun updateLineItem(index: Int, item: DraftPoItem) {
        val updated = _state.value.lineItems.toMutableList()
        if (index in updated.indices) {
            updated[index] = item
            _state.update { it.copy(lineItems = updated) }
        }
    }

    fun removeLineItem(index: Int) {
        val updated = _state.value.lineItems.toMutableList()
        if (index in updated.indices) {
            updated.removeAt(index)
            _state.update { it.copy(lineItems = updated) }
        }
    }

    fun submit() {
        val s = _state.value
        val supplierId = s.selectedSupplierId ?: return
        if (s.lineItems.isEmpty()) {
            _state.value = s.copy(submitError = "Add at least one line item")
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(isSubmitting = true, submitError = null) }
            try {
                val request = PurchaseOrderCreateRequest(
                    supplierId = supplierId,
                    notes = s.notes.takeIf { it.isNotBlank() },
                    expectedDate = s.expectedDate.takeIf { it.isNotBlank() },
                    items = s.lineItems.map { item ->
                        PurchaseOrderItemRequest(
                            inventoryItemId = item.inventoryItemId,
                            quantityOrdered = item.quantityOrdered,
                            costPrice = item.costPrice,
                        )
                    },
                )
                val po = repository.createPurchaseOrder(request)
                _state.update { it.copy(isSubmitting = false, createdPoId = po.id) }
            } catch (e: CancellationException) {
                // BUGHUNT-2026-05-17: purchase orders are real spending
                // commitments to a supplier and the create endpoint has no
                // idempotency key. A "Failed" banner tempted a re-tap that
                // produced a duplicate PO. Clear in-progress state without
                // an actionable error so the user must reopen the sheet.
                _state.update { it.copy(isSubmitting = false) }
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "submit failed: ${e.message}")
                _state.update {
                    it.copy(
                        isSubmitting = false,
                        submitError = e.message ?: "Failed to create purchase order",
                    )
                }
            }
        }
    }

    fun clearSubmitError() {
        _state.update { it.copy(submitError = null) }
    }

    companion object {
        private const val TAG = "POCreateVM"
    }
}
