package com.bizarreelectronics.crm.ui.screens.pos.flows

import com.bizarreelectronics.crm.ui.screens.pos.CartLine

/**
 * Entry point for a standard over-the-counter retail sale.
 *
 * When to use: the customer is buying physical inventory items (accessories,
 * parts in stock, etc.) with no associated service ticket.  This is the
 * simplest sale type — no labor, no ticket linkage needed at creation time.
 *
 * Wave 2 will wire this into PosCoordinator.setLines().
 */
object RetailSaleFlow {

    /**
     * Stamp every [CartLine] with type = "inventory" and return the list.
     *
     * The function is intentionally a pass-through: callers already have
     * their lines with prices; this flow just ensures they carry the correct
     * sale-type tag before being committed to the session.
     *
     * @param items  Lines sourced from inventory search or manual entry.
     * @return       Same lines with [CartLine.type] = "inventory".
     */
    fun create(items: List<CartLine>): List<CartLine> =
        items.map { it.copy(type = "inventory") }
}
