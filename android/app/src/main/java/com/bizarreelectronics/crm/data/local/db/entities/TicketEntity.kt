package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.compose.runtime.Immutable

/**
 * Ticket row. Money columns (subtotal, discount, totalTax, total) are stored as
 * **Long cents** — see [com.bizarreelectronics.crm.util.Money] for helpers.
 */
@Entity(
    tableName = "tickets",
    foreignKeys = [
        ForeignKey(
            entity = CustomerEntity::class,
            parentColumns = ["id"],
            childColumns = ["customer_id"],
            onDelete = ForeignKey.SET_NULL,
        ),
    ],
    indices = [
        Index("customer_id"),
        Index("status_id"),
        Index("assigned_to"),
        Index("created_at"),
    ],
)
@Immutable
data class TicketEntity(
    @PrimaryKey
    val id: Long,

    @ColumnInfo(name = "order_id")
    val orderId: String,

    @ColumnInfo(name = "customer_id")
    val customerId: Long? = null,

    @ColumnInfo(name = "status_id")
    val statusId: Long? = null,

    @ColumnInfo(name = "status_name")
    val statusName: String? = null,

    @ColumnInfo(name = "status_color")
    val statusColor: String? = null,

    @ColumnInfo(name = "status_is_closed")
    val statusIsClosed: Boolean = false,

    @ColumnInfo(name = "assigned_to")
    val assignedTo: Long? = null,

    /** Cents. */
    val subtotal: Long = 0L,

    /** Cents. */
    val discount: Long = 0L,

    /** Cents. */
    @ColumnInfo(name = "total_tax")
    val totalTax: Long = 0L,

    /** Cents. */
    val total: Long = 0L,

    @ColumnInfo(name = "due_on")
    val dueOn: String? = null,

    val signature: String? = null,

    val labels: String? = null,

    @ColumnInfo(name = "invoice_id")
    val invoiceId: Long? = null,

    @ColumnInfo(name = "created_by")
    val createdBy: Long? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: String,

    @ColumnInfo(name = "updated_at")
    val updatedAt: String,

    @ColumnInfo(name = "customer_name")
    val customerName: String? = null,

    @ColumnInfo(name = "customer_phone")
    val customerPhone: String? = null,

    @ColumnInfo(name = "first_device_name")
    val firstDeviceName: String? = null,

    @ColumnInfo(name = "is_deleted")
    val isDeleted: Boolean = false,

    @ColumnInfo(name = "locally_modified")
    val locallyModified: Boolean = false,

    @ColumnInfo(name = "last_synced_at")
    val lastSyncedAt: String? = null,
)
