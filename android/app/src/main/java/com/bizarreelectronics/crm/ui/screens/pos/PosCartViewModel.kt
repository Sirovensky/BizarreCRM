package com.bizarreelectronics.crm.ui.screens.pos

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

data class PosCartUiState(
    val customer: PosAttachedCustomer? = null,
    val lines: List<CartLine> = emptyList(),
    val cartDiscountCents: Long = 0L,
    val editingLineId: String? = null,
    val taxRate: Double = 0.0,
) {
    val subtotalCents: Long get() = lines.sumOf { it.lineTotalCents }
    val taxCents: Long get() = lines.sumOf { it.taxCents }
    val discountCents: Long get() = cartDiscountCents
    val totalCents: Long get() = (subtotalCents + taxCents - cartDiscountCents).coerceAtLeast(0L)

    val editingLine: CartLine? get() = lines.firstOrNull { it.id == editingLineId }
}

@HiltViewModel
class PosCartViewModel @Inject constructor(
    private val coordinator: PosCoordinator,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PosCartUiState())
    val uiState: StateFlow<PosCartUiState> = _uiState.asStateFlow()

    init {
        // Mirror coordinator session into local UI state
        viewModelScope.launch {
            coordinator.session.collect { session ->
                _uiState.update {
                    it.copy(
                        customer = session.customer,
                        lines = session.lines,
                        cartDiscountCents = session.cartDiscountCents,
                    )
                }
            }
        }
    }

    fun addMiscItem(name: String, unitPriceCents: Long) {
        val line = CartLine(
            type = "custom",
            name = name,
            unitPriceCents = unitPriceCents,
            taxRate = _uiState.value.taxRate,
        )
        pushLines(_uiState.value.lines + line)
    }

    fun addInventoryItem(itemId: Long, name: String, unitPriceCents: Long, taxRate: Double = 0.0) {
        val existing = _uiState.value.lines.indexOfFirst { it.itemId == itemId && it.type == "inventory" }
        val updated = if (existing >= 0) {
            _uiState.value.lines.mapIndexed { i, l ->
                if (i == existing) l.copy(qty = l.qty + 1) else l
            }
        } else {
            _uiState.value.lines + CartLine(
                type = "inventory",
                itemId = itemId,
                name = name,
                unitPriceCents = unitPriceCents,
                taxRate = taxRate,
            )
        }
        pushLines(updated)
    }

    /** Called when BarcodeAnalyzer resolves a barcode to an inventory item. */
    fun onBarcodeResolved(itemId: Long, name: String, priceCents: Long) =
        addInventoryItem(itemId, name, priceCents)

    fun setLineQty(lineId: String, qty: Int) {
        if (qty < 1) return
        val updated = _uiState.value.lines.map { if (it.id == lineId) it.copy(qty = qty.coerceIn(1, 999)) else it }
        pushLines(updated)
    }

    fun setLineDiscount(lineId: String, discountCents: Long) {
        val updated = _uiState.value.lines.map { if (it.id == lineId) it.copy(discountCents = discountCents) else it }
        pushLines(updated)
    }

    fun setLineNote(lineId: String, note: String) {
        val updated = _uiState.value.lines.map { if (it.id == lineId) it.copy(note = note.take(1000)) else it }
        pushLines(updated)
    }

    fun removeLine(lineId: String) {
        pushLines(_uiState.value.lines.filter { it.id != lineId })
        if (_uiState.value.editingLineId == lineId) dismissLineEdit()
    }

    fun setCartDiscount(cents: Long) {
        coordinator.setCartDiscount(cents)
    }

    fun detachCustomer() = coordinator.detachCustomer()

    fun openLineEdit(lineId: String) = _uiState.update { it.copy(editingLineId = lineId) }

    fun dismissLineEdit() = _uiState.update { it.copy(editingLineId = null) }

    private fun pushLines(lines: List<CartLine>) {
        coordinator.setLines(lines)
    }
}
