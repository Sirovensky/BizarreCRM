package com.bizarreelectronics.crm.ui.screens.pos

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
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
    val scanMessage: String? = null,
    /** Linked repair-ticket draft id — drives the "Ticket draft" topbar subtitle */
    val linkedTicketId: Long? = null,
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
    private val inventoryApi: InventoryApi,
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
                        linkedTicketId = session.linkedTicketId,
                    )
                }
            }
        }
        // POS-TAX-001: load the default tax class rate from
        // /api/v1/settings/tax-classes so cart totals show real tax (mockup
        // PHONE 3 'Tax · 8.5%'). Falls back to 0.0 on a missing default
        // row so the cart still renders without a tax line in dev DBs.
        viewModelScope.launch {
            runCatching { inventoryApi.getTaxClasses() }
                .onSuccess { resp ->
                    val classes = resp.data.orEmpty()
                    // tax_classes.rate is stored as a PERCENT (e.g. 8.5 for
                    // 8.5%) on the server (matches invoices.routes.ts +
                    // pos.routes.ts /transaction which divide by 100 when
                    // multiplying line nets). Convert to a fraction here so
                    // CartLine.taxCents = lineTotalCents * taxRate gives
                    // sensible cents instead of 886%-of-subtotal totals.
                    val ratePercent = classes.firstOrNull { it.isDefault == 1 }?.rate
                        ?: classes.firstOrNull()?.rate
                        ?: 0.0
                    _uiState.update { it.copy(taxRate = ratePercent / 100.0) }
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

    fun addInventoryItem(
        itemId: Long,
        name: String,
        unitPriceCents: Long,
        sku: String? = null,
        taxRate: Double? = null,
    ) {
        // Use the per-item tax rate if the caller supplied one (e.g. an
        // inventory item with a non-default tax class); otherwise inherit the
        // cart's loaded default rate so the totals row picks up real tax math.
        val effectiveRate = taxRate ?: _uiState.value.taxRate
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
                sku = sku,
                unitPriceCents = unitPriceCents,
                taxRate = effectiveRate,
            )
        }
        pushLines(updated)
    }

    /** Called when BarcodeAnalyzer resolves a barcode to an inventory item. */
    fun onBarcodeResolved(itemId: Long, name: String, priceCents: Long, sku: String? = null) =
        addInventoryItem(itemId, name, priceCents, sku = sku)

    /**
     * Look up a scanned barcode / SKU against `/inventory/barcode/{code}`
     * and add the resolved item to the cart. Surfaces a scanMessage
     * either way so the cart screen can flash a snackbar with the
     * result ("Added: iPhone 14 Pro Screen" or "No item for code 123").
     */
    fun scanBarcode(code: String) {
        val trimmed = code.trim()
        if (trimmed.isBlank()) return
        viewModelScope.launch {
            runCatching { inventoryApi.lookupBarcode(trimmed) }
                .onSuccess { resp ->
                    val item = resp.data?.item
                    if (item == null) {
                        _uiState.update { it.copy(scanMessage = "No item for code $trimmed") }
                        return@onSuccess
                    }
                    val priceCents = ((item.price ?: 0.0) * 100).toLong()
                    addInventoryItem(
                        itemId = item.id,
                        name = item.name ?: "Item #${item.id}",
                        unitPriceCents = priceCents,
                        sku = item.sku,
                    )
                    _uiState.update { it.copy(scanMessage = "Added: ${item.name ?: "item"}") }
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(scanMessage = "Scan lookup failed: ${e.message ?: "network error"}")
                    }
                }
        }
    }

    fun clearScanMessage() = _uiState.update { it.copy(scanMessage = null) }

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
