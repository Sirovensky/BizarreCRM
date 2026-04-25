package com.bizarreelectronics.crm.ui.screens.pos

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.PosApi
import com.bizarreelectronics.crm.data.remote.api.PosCartLineDto
import com.bizarreelectronics.crm.data.remote.api.PosPaymentDto
import com.bizarreelectronics.crm.data.remote.api.PosSaleRequest
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

data class PosTenderUiState(
    val totalCents: Long = 0L,
    val appliedTenders: List<AppliedTender> = emptyList(),
    val isProcessing: Boolean = false,
    val errorMessage: String? = null,
    val completedOrderId: String? = null,
) {
    val paidCents: Long get() = appliedTenders.sumOf { it.amountCents }
    val remainingCents: Long get() = (totalCents - paidCents).coerceAtLeast(0L)
    val paidPercent: Float get() = if (totalCents > 0) (paidCents.toFloat() / totalCents).coerceIn(0f, 1f) else 0f
    val isFullyPaid: Boolean get() = remainingCents == 0L && totalCents > 0L
}

@HiltViewModel
class PosTenderViewModel @Inject constructor(
    private val coordinator: PosCoordinator,
    private val posApi: PosApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PosTenderUiState())
    val uiState: StateFlow<PosTenderUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            coordinator.session.collect { session ->
                _uiState.update {
                    it.copy(
                        totalCents = session.totalCents,
                        appliedTenders = session.appliedTenders,
                    )
                }
            }
        }
    }

    fun applyStoreCredit() {
        val session = coordinator.session.value
        val creditCents = session.customer?.storeCreditCents ?: 0L
        if (creditCents <= 0L) return
        val applyAmount = creditCents.coerceAtMost(_uiState.value.remainingCents)
        val tender = AppliedTender(
            method = "store_credit",
            label = "Store credit",
            amountCents = applyAmount,
            detail = "Used from ${creditCents.toDollarString()} available",
        )
        coordinator.addTender(tender)
    }

    fun applyAch(amountCents: Long) {
        val tender = AppliedTender(
            method = "ach",
            label = "ACH / check",
            amountCents = amountCents.coerceAtMost(_uiState.value.remainingCents),
        )
        coordinator.addTender(tender)
    }

    fun parkCart() {
        // Parking stores the cart for later retrieval — stub for Phase 2
        // Full layaway mode implemented in Phase 3 alongside check-in
    }

    fun removeTender(tenderId: String) = coordinator.removeTender(tenderId)

    /** Stub for Phase 4 BlockChyp integration. */
    @Suppress("UNUSED_PARAMETER")
    fun chargeCard(amountCents: Long) {
        viewModelScope.launch {
            // Phase 4 will replace with real SDK call.
            _uiState.update { it.copy(errorMessage = "Card reader not yet configured — Phase 4") }
        }
    }

    fun finalizeSale() {
        if (!_uiState.value.isFullyPaid) return
        val session = coordinator.session.value
        _uiState.update { it.copy(isProcessing = true, errorMessage = null) }

        viewModelScope.launch {
            val idempotencyKey = UUID.randomUUID().toString()
            val request = PosSaleRequest(
                idempotencyKey = idempotencyKey,
                customerId = session.customer?.id?.takeIf { it > 0L },
                lines = session.lines.map { line ->
                    PosCartLineDto(
                        id = line.id,
                        type = line.type,
                        itemId = line.itemId,
                        name = line.name,
                        qty = line.qty,
                        unitPriceCents = line.unitPriceCents,
                        discountCents = line.discountCents,
                        taxClassId = line.taxClassId,
                        taxRate = line.taxRate,
                        notes = line.note,
                    )
                },
                cartDiscountCents = session.cartDiscountCents,
                paymentMethod = session.appliedTenders.firstOrNull()?.method ?: "card",
                paymentAmountCents = session.paidCents,
                // Server prefers `payments[]` when non-empty so split-tender
                // sales preserve the per-method breakdown on the receipt.
                payments = session.appliedTenders.map { t ->
                    PosPaymentDto(method = t.method, amountCents = t.amountCents)
                },
                linkedTicketId = session.linkedTicketId,
            )

            runCatching {
                posApi.completeSale(idempotencyKey, request)
            }.onSuccess { resp ->
                val data = resp.data
                if (resp.success && data != null) {
                    coordinator.completeOrder(
                        orderId = data.orderId,
                        invoiceId = data.invoiceId,
                        trackingUrl = null, // server embeds tracking URL after POS-RECEIPT-001
                    )
                    _uiState.update { it.copy(isProcessing = false, completedOrderId = data.orderId) }
                } else {
                    _uiState.update { it.copy(isProcessing = false, errorMessage = resp.message ?: "Sale failed") }
                }
            }.onFailure { e ->
                _uiState.update { it.copy(isProcessing = false, errorMessage = e.message ?: "Network error") }
            }
        }
    }

    fun clearError() = _uiState.update { it.copy(errorMessage = null) }
}
