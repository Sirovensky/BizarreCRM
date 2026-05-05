package com.bizarreelectronics.crm.ui.screens.pos.flows

import com.bizarreelectronics.crm.ui.screens.pos.CartLine

/**
 * Entry point for a device or accessory trade-in.
 *
 * When to use: the customer is trading in a device toward a purchase or
 * for cash.  A trade-in reduces the cart total via a negative-priced line.
 *
 * Server-side sync note: when the completed invoice is pushed to the server,
 * lines with type = "trade_in" trigger used-stock creation in the inventory
 * service.  The [sku] field, if supplied, is used to match or create the
 * inventory record.  Without a SKU the server creates a generic entry under
 * "Trade-in Received" that the shop manager can catalog later.
 *
 * Wave 2 will wire this into the PosCoordinator so the cashier can tap
 * "Trade-in" from the cart action bar.
 */
object TradeInFlow {

    /**
     * Build a single trade-in [CartLine] representing the device being
     * traded.
     *
     * The line price is **negative** ([unitPriceCents] = `-valueCents`) so
     * it reduces the cart subtotal.  The quantity is always 1.
     *
     * @param itemName    Display name shown on receipt (e.g. "iPhone 13 trade-in").
     * @param valueCents  Agreed trade-in value in cents (positive integer).
     * @param sku         Optional SKU; if null the server auto-generates one.
     * @return            A [CartLine] ready to be appended to the session lines.
     */
    fun create(
        itemName: String,
        valueCents: Long,
        sku: String? = null,
    ): CartLine = CartLine(
        name = itemName,
        unitPriceCents = -valueCents,
        qty = 1,
        sku = sku,
        type = "trade_in",
    )
}
