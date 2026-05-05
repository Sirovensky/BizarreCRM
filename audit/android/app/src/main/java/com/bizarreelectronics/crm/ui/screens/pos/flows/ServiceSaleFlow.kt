package com.bizarreelectronics.crm.ui.screens.pos.flows

import com.bizarreelectronics.crm.ui.screens.pos.CartLine

/**
 * Entry point for a repair/service sale that combines labor and parts.
 *
 * When to use: the cashier is ringing up a completed repair ticket.  Labor
 * lines and parts lines are kept separate in the coordinator (so they can be
 * displayed in grouped sections on the cart screen) but concatenated into a
 * single line list before submission to the invoice endpoint.
 *
 * Wave 2 will wire this into the "Ready for pickup" ticket → POS flow so
 * that openReadyForPickup() can populate the session via this object.
 */
object ServiceSaleFlow {

    /**
     * Tag and merge [labor] and [parts] into a single ordered list.
     *
     * @param labor  Labor/diagnostic fee lines; stamped type = "service".
     * @param parts  Parts used in the repair; stamped type = "part".
     * @return       Labor lines first, then parts lines, all correctly tagged.
     */
    fun create(labor: List<CartLine>, parts: List<CartLine>): List<CartLine> =
        labor.map { it.copy(type = "service") } +
        parts.map { it.copy(type = "part") }
}
