package com.bizarreelectronics.crm.ui.screens.pos

import java.util.UUID

// ─── Shared domain models used across the entire POS module ──────────────────

data class CartLine(
    val id: String = UUID.randomUUID().toString(),
    val type: String = "inventory",     // "inventory" | "service" | "custom"
    val itemId: Long? = null,
    val name: String,
    val sku: String? = null,
    val qty: Int = 1,
    val unitPriceCents: Long,
    val originalUnitPriceCents: Long? = null,   // set when a manual discount is applied; shown as strikethrough
    val discountCents: Long = 0L,
    val taxClassId: Long? = null,
    val taxRate: Double = 0.0,
    val photoUrl: String? = null,
    val note: String? = null,
    // TODO: populate stockQty from inventory lookup when adding to cart
    val stockQty: Int? = null,
) {
    val lineTotalCents: Long get() = (unitPriceCents * qty) - discountCents
    val taxCents: Long get() = (lineTotalCents * taxRate).toLong()
    val totalWithTaxCents: Long get() = lineTotalCents + taxCents
}

data class PosAttachedCustomer(
    val id: Long,
    val name: String,
    val phone: String? = null,
    val email: String? = null,
    val ticketCount: Int = 0,
    val storeCreditCents: Long = 0L,
)

data class ReadyForPickupTicket(
    val ticketId: Long,
    val orderId: String,
    val deviceName: String,
    val dueCents: Long,
    // AUDIT-005: carry customer identity so openReadyForPickup can attach the
    // customer to the coordinator even when the cashier taps a ticket before
    // the customer-attach step (e.g. future global ticket queue view).
    val customerId: Long = 0L,
    val customerName: String = "",
)

data class PastRepair(
    val ticketId: Long,
    val description: String,
    val date: String,
    val amountCents: Long,
)

data class SearchResultGroup(
    val customers: List<CustomerResult> = emptyList(),
    val tickets: List<TicketResult> = emptyList(),
    val parts: List<PartResult> = emptyList(),
)

data class CustomerResult(
    val id: Long,
    val name: String,
    val phone: String? = null,
    val email: String? = null,
    val ticketCount: Int = 0,
    val initials: String = run {
        val parts = name.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        when {
            parts.isEmpty() -> ""
            parts.size == 1 -> parts[0].take(2).uppercase()
            else -> "${parts.first().first()}${parts.last().first()}".uppercase()
        }
    },
)

data class TicketResult(
    val id: Long,
    val orderId: String,
    val customerName: String,
    val deviceName: String,
    val status: String,
)

data class PartResult(
    val id: Long,
    val name: String,
    val sku: String? = null,
    val priceCents: Long,
    val stockQty: Int = 0,
)

enum class DiscountChip { FIVE_PCT, TEN_PCT, FLAT, CUSTOM }

data class AppliedTender(
    val id: String = UUID.randomUUID().toString(),
    val method: String,          // "card" | "nfc" | "ach" | "store_credit" | "cash" | "park"
    val label: String,
    val amountCents: Long,
    val detail: String? = null,
)

/** Format cents to "$NNN.NN" display string. Handles negatives as "-$N.NN". */
fun Long.toDollarString(): String {
    val negative = this < 0
    val abs = Math.abs(this)
    val dollars = abs / 100
    val cents = abs % 100
    val sign = if (negative) "-" else ""
    return "$sign${'$'}$dollars.${cents.toString().padStart(2, '0')}"
}
