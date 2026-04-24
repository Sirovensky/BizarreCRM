package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Room entity for a parked POS cart.
 *
 * Parked carts are stored offline so the cashier can serve multiple customers
 * without losing progress. The cart JSON is a serialized [PosCartState].
 *
 * Plan §16.1 L1800 — parked cart offline persistence.
 */
@Entity(tableName = "parked_carts")
data class ParkedCartEntity(
    @PrimaryKey
    val id: String, // UUID generated at park time

    /** Human-readable label, e.g. customer name or "Cart 1". */
    val label: String,

    /** Serialized JSON of the PosCartState. */
    @ColumnInfo(name = "cart_json")
    val cartJson: String,

    /** Epoch-ms when this cart was parked. */
    @ColumnInfo(name = "parked_at")
    val parkedAt: Long = System.currentTimeMillis(),

    /** Optional customer id for quick display. */
    @ColumnInfo(name = "customer_id")
    val customerId: Long? = null,

    /** Optional customer name for list display. */
    @ColumnInfo(name = "customer_name")
    val customerName: String? = null,

    /** Cart subtotal in cents for display. */
    @ColumnInfo(name = "subtotal_cents")
    val subtotalCents: Long = 0L,
)
