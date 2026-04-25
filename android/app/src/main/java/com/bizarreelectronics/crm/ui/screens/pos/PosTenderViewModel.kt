package com.bizarreelectronics.crm.ui.screens.pos

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.dao.ParkedCartDao
import com.bizarreelectronics.crm.data.local.db.entities.ParkedCartEntity
import com.bizarreelectronics.crm.data.remote.api.PosApi
import com.bizarreelectronics.crm.data.remote.api.PosCartLineDto
import com.bizarreelectronics.crm.data.remote.api.PosPaymentDto
import com.bizarreelectronics.crm.data.remote.api.PosSaleRequest
import com.google.gson.Gson
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
    val attachedCustomerStoreCreditCents: Long = 0L,
) {
    val paidCents: Long get() = appliedTenders.sumOf { it.amountCents }
    val remainingCents: Long get() = (totalCents - paidCents).coerceAtLeast(0L)
    val paidPercent: Float get() = if (totalCents > 0) (paidCents.toFloat() / totalCents).coerceIn(0f, 1f) else 0f
    // POS-AUDIT-002: mirror PosCoordinator — $0.00 cart is finalizable when
    // tenders cover it (or total is already 0); cart-empty guard lives in coordinator.
    val isFullyPaid: Boolean get() = remainingCents == 0L && totalCents >= 0L
}

@HiltViewModel
class PosTenderViewModel @Inject constructor(
    private val coordinator: PosCoordinator,
    private val posApi: PosApi,
    private val parkedCartDao: ParkedCartDao,
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
                        attachedCustomerStoreCreditCents = session.customer?.storeCreditCents ?: 0L,
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

    /**
     * Cash tender: cashier types received amount; we apply min(received, remaining)
     * as the tender amount and surface change-due in the detail string when
     * received > remaining (matches mockup PHONE 5 'Received \$100 · change \$2.00 due').
     */
    fun applyCash(receivedCents: Long) {
        val remaining = _uiState.value.remainingCents
        if (receivedCents <= 0L) return
        val applied = receivedCents.coerceAtMost(remaining)
        val change = (receivedCents - remaining).coerceAtLeast(0L)
        val detail = if (change > 0L) {
            "Received ${receivedCents.toDollarString()} · change ${change.toDollarString()} due"
        } else null
        coordinator.addTender(
            AppliedTender(
                method = "cash",
                label = "Cash",
                amountCents = applied,
                detail = detail,
            )
        )
    }

    /**
     * AUDIT-011: snapshot the current session into Room so the cashier can
     * resume it later from the Parked Carts screen.  After persisting, the
     * active session is reset so the POS returns to its idle state.
     *
     * cart_json stores the full PosSession as Gson-serialized JSON; the
     * unparking side deserialises it and calls coordinator.setLines /
     * attachCustomer to restore state (Phase 3 follow-up).
     */
    fun parkCart() {
        val session = coordinator.session.value
        if (session.lines.isEmpty()) {
            _uiState.update { it.copy(errorMessage = "Nothing to park — cart is empty") }
            return
        }
        viewModelScope.launch {
            val id = UUID.randomUUID().toString()
            val label = session.customer
                ?.name?.takeIf { it.isNotBlank() }
                ?: "Cart ${id.take(6).uppercase()}"
            val entity = ParkedCartEntity(
                id = id,
                label = label,
                cartJson = Gson().toJson(session),
                parkedAt = System.currentTimeMillis(),
                customerId = session.customer?.id?.takeIf { it > 0L },
                customerName = session.customer?.name,
                subtotalCents = session.subtotalCents,
            )
            parkedCartDao.upsert(entity)
            coordinator.resetSession()
            _uiState.update { it.copy(errorMessage = "Cart parked — ${session.lines.size} item(s) saved") }
        }
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
                notes = session.cartNote,
            )

            runCatching {
                posApi.completeSale(idempotencyKey, request)
            }.onSuccess { resp ->
                val data = resp.data
                if (resp.success && data != null) {
                    coordinator.completeOrder(
                        orderId = data.orderId,
                        invoiceId = data.invoiceId,
                        trackingUrl = data.trackingUrl, // null until POS-RECEIPT-001 deployed; VM falls back to /track/<orderId>
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
