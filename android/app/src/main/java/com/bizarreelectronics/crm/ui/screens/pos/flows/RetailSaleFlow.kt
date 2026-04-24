package com.bizarreelectronics.crm.ui.screens.pos.flows

import com.bizarreelectronics.crm.ui.screens.pos.CartLine
import com.bizarreelectronics.crm.ui.screens.pos.PosCartState

/**
 * §16.7 — Retail sale flow (inventory items only).
 *
 * Validates that every line is type "inventory", computes totals, and
 * produces a [SaleRequest] ready for [PosApi.completeSale].
 *
 * Does NOT touch the UI layer — pure domain logic, fully unit-testable.
 */
object RetailSaleFlow {

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
        val notes: String? = null,
    )

    fun validate(cart: PosCartState): ValidationResult {
        if (cart.lines.isEmpty()) {
            return ValidationResult.Error("Cart is empty")
        }
        val nonInventory = cart.lines.filter { it.type != "inventory" }
        if (nonInventory.isNotEmpty()) {
            return ValidationResult.Error(
                "Retail flow only handles inventory items. " +
                    "Found service/custom lines: ${nonInventory.joinToString { it.name }}"
            )
        }
        if (cart.totalCents < 0) {
            return ValidationResult.Error("Total cannot be negative")
        }
        return ValidationResult.Ok
    }

    fun buildRequest(
        cart: PosCartState,
        idempotencyKey: String,
        paymentMethod: String,
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
            notes = notes,
        )
    }
}
