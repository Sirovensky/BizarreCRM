package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Fts4

/**
 * FTS4 virtual table shadowing [TicketEntity] for prefix-aware full-text search.
 *
 * Mirrors the text fields most useful for ticket search:
 *  - [orderId] — order number / ticket ID (e.g. T-1042)
 *  - [statusName] — status label
 *  - [customerName] — denormalized customer name on the ticket row
 *  - [customerPhone] — denormalized phone on the ticket row
 *  - [firstDeviceName] — first device associated with the ticket
 *  - [labels] — comma-separated labels / tags
 *
 * IMEI is stored on `ticket_devices`, not on `tickets` itself, so it cannot
 * be indexed by this FTS table. A separate LIKE query on `ticket_devices.imei`
 * is used for IMEI-targeted search (see [TicketDao.searchByImei]).
 *
 * Sync strategy: AFTER INSERT / AFTER UPDATE / AFTER DELETE triggers on
 * `tickets` (added in MIGRATION_11_12) keep this table current automatically.
 */
@Fts4(contentEntity = TicketEntity::class)
@Entity(tableName = "tickets_fts")
data class TicketFtsEntity(
    @ColumnInfo(name = "order_id")         val orderId: String,
    @ColumnInfo(name = "status_name")      val statusName: String?,
    @ColumnInfo(name = "customer_name")    val customerName: String?,
    @ColumnInfo(name = "customer_phone")   val customerPhone: String?,
    @ColumnInfo(name = "first_device_name") val firstDeviceName: String?,
    val labels: String?,
)
