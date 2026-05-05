package com.bizarreelectronics.crm.ui.screens.pos

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Singleton that carries POS state across the Entry → Cart → Tender → Receipt
 * sub-flow. ViewModels read/write through this coordinator instead of passing
 * large bundles through nav args (which would require URI encoding all fields).
 *
 * Scoped to the application Hilt component so it survives nav back-stack.
 */
@Singleton
class PosCoordinator @Inject constructor() {

    data class PosSession(
        val customer: PosAttachedCustomer? = null,
        val lines: List<CartLine> = emptyList(),
        val cartDiscountCents: Long = 0L,
        val cartNote: String? = null,
        val linkedTicketId: Long? = null,
        val appliedTenders: List<AppliedTender> = emptyList(),
        val completedOrderId: String? = null,
        val completedInvoiceId: Long? = null,
        val trackingUrl: String? = null,
        /** Tip amount in cents. TODO: tenant tip config from server settings. */
        val tipCents: Long = 0L,
    ) {
        val subtotalCents: Long get() = lines.sumOf { it.lineTotalCents }
        val taxCents: Long get() = lines.sumOf { it.taxCents }
        // TASK-1: tip is added on top of the discounted + taxed subtotal
        val totalCents: Long get() = (subtotalCents + taxCents - cartDiscountCents + tipCents).coerceAtLeast(0L)
        val paidCents: Long get() = appliedTenders.sumOf { it.amountCents }
        val remainingCents: Long get() = (totalCents - paidCents).coerceAtLeast(0L)
        // POS-AUDIT-002: allow $0.00 totals (fully-discounted / store-credit-covered).
        // Guard on lines.isNotEmpty() to keep the empty-cart case un-finalizable.
        val isFullyPaid: Boolean get() = remainingCents == 0L && lines.isNotEmpty()
    }

    private val _session = MutableStateFlow(PosSession())
    val session: StateFlow<PosSession> = _session.asStateFlow()

    fun attachCustomer(customer: PosAttachedCustomer) =
        _session.update { it.copy(customer = customer) }

    fun detachCustomer() =
        _session.update { it.copy(customer = null) }

    fun setLines(lines: List<CartLine>) =
        _session.update { it.copy(lines = lines) }

    fun setCartDiscount(cents: Long) =
        _session.update { it.copy(cartDiscountCents = cents) }

    fun setCartNote(note: String) =
        _session.update { it.copy(cartNote = note.ifBlank { null }) }

    fun setLinkedTicket(ticketId: Long?) =
        _session.update { it.copy(linkedTicketId = ticketId) }

    fun addTender(tender: AppliedTender) =
        _session.update { it.copy(appliedTenders = it.appliedTenders + tender) }

    fun removeTender(tenderId: String) =
        _session.update { s ->
            s.copy(appliedTenders = s.appliedTenders.filter { it.id != tenderId })
        }

    /** TASK-1: set tip for the current session. */
    fun setTip(cents: Long) =
        _session.update { it.copy(tipCents = cents.coerceAtLeast(0L)) }

    fun completeOrder(orderId: String, invoiceId: Long, trackingUrl: String?) =
        _session.update {
            it.copy(
                completedOrderId = orderId,
                completedInvoiceId = invoiceId,
                trackingUrl = trackingUrl,
            )
        }

    fun resetSession() {
        _session.value = PosSession()
    }
}
