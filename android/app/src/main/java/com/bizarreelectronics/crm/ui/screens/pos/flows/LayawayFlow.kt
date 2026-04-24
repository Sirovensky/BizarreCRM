package com.bizarreelectronics.crm.ui.screens.pos.flows

import com.bizarreelectronics.crm.ui.screens.pos.PosCartState
import java.time.LocalDate

/**
 * §16.7 — Layaway flow.
 *
 * Customer pays a deposit now; the balance is due later. Creates a layaway
 * invoice on the server with:
 *   - status = "layaway"
 *   - deposit_amount = [depositCents]
 *   - balance_due_date = [balanceDueDate]
 *
 * The server's /api/v1/invoices endpoint handles the "layaway" status and
 * sets the balance-due date. [PosApi.createInvoiceLater] is reused for
 * layaway requests.
 *
 * The remaining balance appears on the customer account until paid or
 * cancelled. Fulfilment (picking up the item) triggers a second POS sale
 * for the balance only.
 */
object LayawayFlow {

    sealed class ValidationResult {
        object Ok : ValidationResult()
        data class Error(val message: String) : ValidationResult()
    }

    data class LayawayRequest(
        val idempotencyKey: String,
        val cart: PosCartState,
        val depositCents: Long,
        val balanceCents: Long,
        val balanceDueDate: LocalDate,
        val customerId: Long?,
        val paymentMethod: String,  // payment method for the deposit
        val notes: String? = null,
    )

    private const val MIN_DEPOSIT_PERCENT = 20   // 20% minimum deposit

    fun validate(
        cart: PosCartState,
        depositCents: Long,
        balanceDueDate: LocalDate,
    ): ValidationResult {
        if (cart.lines.isEmpty()) {
            return ValidationResult.Error("Cart is empty")
        }
        if (cart.customer == null) {
            return ValidationResult.Error("Layaway requires an attached customer")
        }
        if (depositCents <= 0L) {
            return ValidationResult.Error("Deposit must be greater than zero")
        }
        val minDeposit = cart.totalCents * MIN_DEPOSIT_PERCENT / 100L
        if (depositCents < minDeposit) {
            return ValidationResult.Error(
                "Minimum deposit is $MIN_DEPOSIT_PERCENT% of total ($minDeposit¢)"
            )
        }
        if (depositCents >= cart.totalCents) {
            return ValidationResult.Error("Deposit covers full amount — use regular sale instead")
        }
        if (!balanceDueDate.isAfter(LocalDate.now())) {
            return ValidationResult.Error("Balance due date must be in the future")
        }
        return ValidationResult.Ok
    }

    fun buildRequest(
        cart: PosCartState,
        idempotencyKey: String,
        depositCents: Long,
        balanceDueDate: LocalDate,
        paymentMethod: String,
        notes: String? = null,
    ): LayawayRequest {
        val balance = (cart.totalCents - depositCents).coerceAtLeast(0L)
        return LayawayRequest(
            idempotencyKey = idempotencyKey,
            cart = cart,
            depositCents = depositCents,
            balanceCents = balance,
            balanceDueDate = balanceDueDate,
            customerId = cart.customer?.id,
            paymentMethod = paymentMethod,
            notes = notes,
        )
    }
}
