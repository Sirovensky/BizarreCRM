package com.bizarreelectronics.crm.ui.screens.pos

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.dao.ParkedCartDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.ParkedCartEntity
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.PosApi
import com.bizarreelectronics.crm.data.remote.api.PosCartLineDto
import com.bizarreelectronics.crm.data.remote.api.PosGiftCardRedeemRequest
import com.bizarreelectronics.crm.data.remote.api.PosInvoiceLaterRequest
import com.bizarreelectronics.crm.data.remote.api.PosPaymentDto
import com.bizarreelectronics.crm.data.remote.api.PosSaleRequest
import com.bizarreelectronics.crm.ui.screens.pos.components.JurisdictionRule
import com.bizarreelectronics.crm.ui.screens.pos.components.PosTaxCalculator
import com.bizarreelectronics.crm.ui.screens.pos.components.TenantTaxConfig
import com.bizarreelectronics.crm.ui.screens.pos.components.TaxBreakdown
import com.bizarreelectronics.crm.ui.screens.pos.CashDrawerControllerStub
import com.bizarreelectronics.crm.util.NetworkMonitor
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
    /** True when the last finalizeSale was saved to the offline queue (no network). */
    val savedOffline: Boolean = false,
    /** True when no customer is attached (used to disable Invoice Later tile). */
    val hasAttachedCustomer: Boolean = false,
    // TASK-4: offline banner fields
    val isOnline: Boolean = true,
    val pendingSaleCount: Int = 0,
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
    private val cashDrawerController: CashDrawerControllerStub,
    private val networkMonitor: NetworkMonitor,
    private val syncQueueDao: SyncQueueDao,
    private val authPreferences: AuthPreferences,
    private val gson: Gson,
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
                        hasAttachedCustomer = session.customer != null && session.customer.id > 0L,
                    )
                }
            }
        }
        // TASK-4: observe network state
        viewModelScope.launch {
            networkMonitor.isOnline.collect { online ->
                _uiState.update { it.copy(isOnline = online) }
            }
        }
        // TASK-4: observe pending pos_sale count
        viewModelScope.launch {
            syncQueueDao.getCount().collect { _ ->
                val count = syncQueueDao.countPendingByOpType("pos_sale")
                _uiState.update { it.copy(pendingSaleCount = count) }
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

    // ─── Task 1: Gift card ────────────────────────────────────────────────────

    /**
     * Redeem a gift card code against the remaining balance.
     * On success, adds an [AppliedTender] with method="gift_card".
     * On failure, surfaces the error message via snackbar.
     */
    fun applyGiftCard(code: String) {
        val remaining = _uiState.value.remainingCents
        // session 2026-04-26 — RACE: move isProcessing guard before launch so a second tap cannot
        // slip through the window between launch() and the first _uiState.update inside the coroutine.
        if (remaining <= 0L || _uiState.value.isProcessing) return
        _uiState.update { it.copy(isProcessing = true, errorMessage = null) }
        viewModelScope.launch {
            runCatching {
                posApi.redeemGiftCard(PosGiftCardRedeemRequest(code = code.trim(), amountCents = remaining))
            }.onSuccess { resp ->
                val data = resp.data
                if (resp.success && data != null) {
                    val remainingOnCard = data.remainingCents
                    coordinator.addTender(
                        AppliedTender(
                            method = "gift_card",
                            label = "Gift Card",
                            amountCents = data.appliedCents,
                            detail = "Remaining ${remainingOnCard.toDollarString()} on card",
                        )
                    )
                    _uiState.update { it.copy(isProcessing = false) }
                } else {
                    _uiState.update { it.copy(isProcessing = false, errorMessage = resp.message ?: "Gift card redemption failed") }
                }
            }.onFailure { e ->
                _uiState.update { it.copy(isProcessing = false, errorMessage = e.message ?: "Gift card error") }
            }
        }
    }

    // ─── Task 2: Invoice later ────────────────────────────────────────────────

    /**
     * Create an invoice-later for the current cart. Requires an attached customer.
     * On success, sets [completedOrderId] so the receipt screen fires.
     */
    fun invoiceLater() {
        val session = coordinator.session.value
        val customerId = session.customer?.id?.takeIf { it > 0L }
        if (customerId == null) {
            _uiState.update { it.copy(errorMessage = "Attach a customer before invoicing later") }
            return
        }
        _uiState.update { it.copy(isProcessing = true, errorMessage = null) }
        viewModelScope.launch {
            val idempotencyKey = UUID.randomUUID().toString()
            val request = PosInvoiceLaterRequest(
                idempotencyKey = idempotencyKey,
                customerId = customerId,
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
                notes = session.cartNote,
            )
            runCatching {
                posApi.createInvoiceLater(idempotencyKey, request)
            }.onSuccess { resp ->
                val data = resp.data
                if (resp.success && data != null) {
                    coordinator.completeOrder(
                        orderId = data.orderId,
                        invoiceId = data.invoiceId,
                        trackingUrl = data.trackingUrl,
                    )
                    _uiState.update { it.copy(isProcessing = false, completedOrderId = data.orderId) }
                } else {
                    _uiState.update { it.copy(isProcessing = false, errorMessage = resp.message ?: "Invoice later failed") }
                }
            }.onFailure { e ->
                _uiState.update { it.copy(isProcessing = false, errorMessage = e.message ?: "Network error") }
            }
        }
    }

    // ─── Task 3: Split tender (evenly) ───────────────────────────────────────

    /**
     * Split the remaining balance evenly into [parts] cash tenders.
     * Each part gets `remainingCents / parts`; the last part absorbs
     * any rounding remainder so the total still covers the balance exactly.
     *
     * MVP: all parts are method="cash" so the cashier can collect individual
     * amounts. Per-tender method choice is TODO POS-SPLIT-METHOD-001 (Phase 2).
     */
    fun splitEvenly(parts: Int) {
        if (parts < 2) return
        val remaining = _uiState.value.remainingCents
        if (remaining <= 0L) return
        val baseAmount = remaining / parts
        for (i in 1..parts) {
            val amount = if (i == parts) remaining - baseAmount * (parts - 1) else baseAmount
            applyCash(amount)
        }
    }

    // ─── Task 5: Manual cash drawer open ─────────────────────────────────────

    /**
     * Open the cash drawer manually (role-gated admin-only).
     * Reads [AuthPreferences.userRole] + [AuthPreferences.userId] at call time.
     * Failure (non-admin, no printer) is surfaced as snackbar, not a crash.
     */
    fun openCashDrawerManual(reason: String) {
        val role = authPreferences.userRole ?: ""
        val operatorId = authPreferences.userId.toString()
        viewModelScope.launch {
            runCatching {
                cashDrawerController.manualOpen(
                    operatorId = operatorId,
                    operatorRole = role,
                    reason = reason,
                )
            }.onSuccess { result ->
                result.onFailure { e ->
                    _uiState.update { it.copy(errorMessage = e.message ?: "Could not open drawer") }
                }
            }.onFailure { e ->
                _uiState.update { it.copy(errorMessage = e.message ?: "Could not open drawer") }
            }
        }
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
                cartJson = gson.toJson(session),
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
        // session 2026-04-26 — RACE: guard isProcessing so rapid double-tap cannot launch a second
        // coroutine before the first sets isProcessing = true (each coroutine generates its own UUID,
        // so idempotency key would NOT deduplicate them).
        if (!_uiState.value.isFullyPaid || _uiState.value.isProcessing) return
        val session = coordinator.session.value
        _uiState.update { it.copy(isProcessing = true, errorMessage = null) }

        viewModelScope.launch {
            // ── Task 6: Tax engine integration ────────────────────────────────
            // Build a PosCartState from the coordinator session and run it through
            // PosTaxCalculator. Fall back to a single-jurisdiction config using
            // the per-line taxRate already stored on each CartLine (first line's
            // rate used as the config rate; 0 when no lines).
            // TODO POS-TAX-MULTI-001: replace with real TenantTaxConfig from
            //   TenantSettingsRepository once that repository exists.
            val taxBreakdownMap: Map<String, Long>? = run {
                val taxExempt = session.customer?.taxExempt == true
                if (taxExempt) {
                    // Tax-exempt customer — no tax on any line.
                    mapOf<String, Long>()
                } else {
                    // taxRate is a decimal fraction (e.g. 0.08 = 8%). Basis points = rate * 10000.
                    val fallbackRateBps = ((session.lines.firstOrNull()?.taxRate ?: 0.0) * 10_000).toInt()
                    val fallbackConfig = TenantTaxConfig(
                        jurisdictions = if (fallbackRateBps > 0)
                            listOf(JurisdictionRule(
                                jurisdictionId = "default",
                                name = "Tax",
                                rateBps = fallbackRateBps,
                            ))
                        else emptyList()
                    )
                    val cart = PosCartState(
                        lines = session.lines,
                        customer = session.customer?.let {
                            AttachedCustomer(id = it.id, name = it.name, taxExempt = it.taxExempt)
                        },
                    )
                    val breakdown: TaxBreakdown = PosTaxCalculator.calculate(cart = cart, config = fallbackConfig)
                    breakdown.jurisdictions.associate { it.jurisdictionId to it.taxCents }
                        .takeIf { it.isNotEmpty() }
                }
            }

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
                discount = session.cartDiscountCents / 100.0,
                tip = 0.0,
                paymentMethod = session.appliedTenders.firstOrNull()?.method ?: "card",
                paymentAmount = session.paidCents / 100.0,
                // Server prefers `payments[]` when non-empty so split-tender
                // sales preserve the per-method breakdown on the receipt.
                payments = session.appliedTenders.map { t ->
                    PosPaymentDto(method = t.method, amountCents = t.amountCents)
                },
                linkedTicketId = session.linkedTicketId,
                notes = session.cartNote,
                taxBreakdown = taxBreakdownMap,
            )

            // ── Task 7: Offline queue ─────────────────────────────────────────
            // Cash sales don't need the network — they complete locally. Any other
            // tender type is queued for sync when offline.
            val isOnline = networkMonitor.isCurrentlyOnline()
            if (!isOnline) {
                // Enqueue to sync queue; navigate to receipt with a temp order id.
                runCatching {
                    syncQueueDao.insert(
                        SyncQueueEntity(
                            entityType = "pos_sale",
                            entityId = 0L,
                            operation = "create",
                            payload = gson.toJson(request),
                            idempotencyKey = idempotencyKey,
                        )
                    )
                }
                val tempOrderId = "OFFLINE-${idempotencyKey.take(8).uppercase()}"
                coordinator.completeOrder(orderId = tempOrderId, invoiceId = 0L, trackingUrl = null)
                _uiState.update {
                    it.copy(
                        isProcessing = false,
                        savedOffline = true,
                        errorMessage = "Saved offline — will sync when connected",
                        completedOrderId = tempOrderId,
                    )
                }
                return@launch
            }

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

                    // ── Task 4: Cash drawer auto-kick ─────────────────────────
                    // Only kick when at least one cash tender was applied.
                    // Failure must not block sale completion.
                    val hasCash = session.appliedTenders.any { it.method == "cash" }
                    if (hasCash) {
                        viewModelScope.launch {
                            runCatching { cashDrawerController.openDrawer() }
                            // Result intentionally ignored — hardware failure is
                            // non-fatal for a completed sale.
                        }
                    }
                } else {
                    _uiState.update { it.copy(isProcessing = false, errorMessage = resp.message ?: "Sale failed") }
                }
            }.onFailure { e ->
                _uiState.update { it.copy(isProcessing = false, errorMessage = e.message ?: "Network error") }
            }
        }
    }

    fun clearError() = _uiState.update { it.copy(errorMessage = null) }

    /** Surface an informational message via the snackbar (reuses errorMessage slot). */
    fun showMessage(message: String) = _uiState.update { it.copy(errorMessage = message) }
}
