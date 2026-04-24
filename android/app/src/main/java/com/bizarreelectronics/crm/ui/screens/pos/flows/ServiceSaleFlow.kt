package com.bizarreelectronics.crm.ui.screens.pos.flows

import com.bizarreelectronics.crm.ui.screens.pos.CartLine
import com.bizarreelectronics.crm.ui.screens.pos.PosCartState

/**
 * §16.7 — Service sale flow (labor + parts, mixed, and ticket-completion).
 *
 * Accepts lines of any type ("inventory", "service", "custom"). When a
 * [ticketId] is provided the request completes the existing ticket.
 *
 * Mixed sales (ticket completion) reuse this flow — the caller passes the
 * ticket id and all cart lines from the ticket's parts/labor.
 *
 * Deposit collection (partial from ticket) is handled by passing
 * [isDeposit] = true and a [depositAmountCents] — the resulting request
 * hits the existing ticket-create-deposit path on the server.
 */
object ServiceSaleFlow {

    sealed class ValidationResult {
        object Ok : ValidationResult()
        data class Error(val message: String) : ValidationResult()
    }

    data class SaleRequest(
        val idempotencyKey: String,
        val lines: List<CartLine>,
        val subtotalCents: Long,
        val taxCents: Long,
        val discountCents: Long,
        val tipCents: Long,
        val totalCents: Long,
        val customerId: Long?,
        val paymentMethod: String,
        val ticketId: Long? = null,
        val isDeposit: Boolean = false,
        val depositAmountCents: Long? = null,
        val notes: String? = null,
    )

    fun validate(cart: PosCartState, isDeposit: Boolean, depositAmountCents: Long?): ValidationResult {
        if (cart.lines.isEmpty()) {
            return ValidationResult.Error("Cart is empty")
        }
        if (isDeposit) {
            if (depositAmountCents == null || depositAmountCents <= 0L) {
                return ValidationResult.Error("Deposit amount must be greater than zero")
            }
            if (depositAmountCents > cart.totalCents) {
                return ValidationResult.Error("Deposit ($depositAmountCents¢) exceeds total (${cart.totalCents}¢)")
            }
        }
        return ValidationResult.Ok
    }

    fun buildRequest(
        cart: PosCartState,
        idempotencyKey: String,
        paymentMethod: String,
        ticketId: Long? = null,
        isDeposit: Boolean = false,
        depositAmountCents: Long? = null,
        notes: String? = null,
    ): SaleRequest {
        return SaleRequest(
            idempotencyKey = idempotencyKey,
            lines = cart.lines,
            subtotalCents = cart.subtotalCents,
            taxCents = cart.taxCents,
            discountCents = cart.discountCents,
            tipCents = cart.tipCents,
            totalCents = cart.totalCents,
            customerId = cart.customer?.id,
            paymentMethod = paymentMethod,
            ticketId = ticketId,
            isDeposit = isDeposit,
            depositAmountCents = depositAmountCents,
            notes = notes,
        )
    }
}
