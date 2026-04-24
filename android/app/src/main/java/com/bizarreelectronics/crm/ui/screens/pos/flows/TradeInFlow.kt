package com.bizarreelectronics.crm.ui.screens.pos.flows

import com.bizarreelectronics.crm.ui.screens.pos.CartLine
import com.bizarreelectronics.crm.ui.screens.pos.PosCartState
import java.util.UUID

/**
 * §16.7 — Trade-in flow.
 *
 * A trade-in is represented as a NEGATIVE inventory line item in the cart.
 * The negative amount reduces the sale total (the customer pays less).
 * On completion the traded-in item is added to used-stock inventory at the
 * trade-in value via a separate POST /inventory (handled by server).
 *
 * Caller adds a trade-in line with [buildTradeInLine] then appends it to
 * the POS cart. The [SaleRequest] includes a non-null [tradeInItems] list
 * so the server knows to create used-stock entries.
 */
object TradeInFlow {

    data class TradeInItem(
        val name: String,
        val condition: String,       // "good" | "fair" | "poor"
        val valueCents: Long,        // positive; stored negative in cart line
        val sku: String? = null,
    )

    data class SaleRequest(
        val idempotencyKey: String,
        val baseCart: PosCartState,
        val tradeInItems: List<TradeInItem>,
        val paymentMethod: String,
        val customerId: Long?,
        val totalAfterTradeInCents: Long,
    )

    sealed class ValidationResult {
        object Ok : ValidationResult()
        data class Error(val message: String) : ValidationResult()
    }

    /** Build a negative CartLine representing the trade-in credit. */
    fun buildTradeInLine(item: TradeInItem): CartLine {
        return CartLine(
            id = UUID.randomUUID().toString(),
            type = "custom",
            name = "Trade-in: ${item.name} (${item.condition})",
            qty = 1,
            unitPriceCents = -item.valueCents,   // negative price = credit
            taxRate = 0.0,                        // trade-ins typically untaxed
        )
    }

    fun validate(cart: PosCartState, tradeIns: List<TradeInItem>): ValidationResult {
        if (tradeIns.isEmpty()) {
            return ValidationResult.Error("No trade-in items specified")
        }
        val totalTradeIn = tradeIns.sumOf { it.valueCents }
        if (totalTradeIn <= 0) {
            return ValidationResult.Error("Trade-in value must be positive")
        }
        return ValidationResult.Ok
    }

    fun buildRequest(
        cart: PosCartState,
        tradeIns: List<TradeInItem>,
        idempotencyKey: String,
        paymentMethod: String,
    ): SaleRequest {
        val tradeInTotal = tradeIns.sumOf { it.valueCents }
        val totalAfterTradeIn = (cart.totalCents - tradeInTotal).coerceAtLeast(0L)
        return SaleRequest(
            idempotencyKey = idempotencyKey,
            baseCart = cart,
            tradeInItems = tradeIns,
            paymentMethod = paymentMethod,
            customerId = cart.customer?.id,
            totalAfterTradeInCents = totalAfterTradeIn,
        )
    }
}
