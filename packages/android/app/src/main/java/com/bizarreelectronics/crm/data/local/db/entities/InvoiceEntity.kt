package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.compose.runtime.Immutable

/**
 * Invoice row.
 *
 * Money columns (subtotal, discount, totalTax, total, amountPaid, amountDue) are
 * stored as **Long cents** (e.g. 1234 = $12.34). Never add a new money column
 * as Double — IEEE-754 rounding drift compounds across thousands of rows.
 *
 * Use [com.bizarreelectronics.crm.util.toCents] / [com.bizarreelectronics.crm.util.toCentsOrZero]
 * to convert API Doubles to the stored type, and [com.bizarreelectronics.crm.util.formatAsMoney]
 * for display.
 */
@Entity(
    tableName = "invoices",
    foreignKeys = [
        ForeignKey(
            entity = TicketEntity::class,
            parentColumns = ["id"],
            childColumns = ["ticket_id"],
            onDelete = ForeignKey.SET_NULL,
        ),
        ForeignKey(
            entity = CustomerEntity::class,
            parentColumns = ["id"],
            childColumns = ["customer_id"],
            onDelete = ForeignKey.SET_NULL,
        ),
    ],
    indices = [
        Index("ticket_id"),
        Index("customer_id"),
        Index("status"),
        Index("created_at"),
    ],
)
@Immutable
data class InvoiceEntity(
    @PrimaryKey
    val id: Long,

    @ColumnInfo(name = "order_id")
    val orderId: String,

    @ColumnInfo(name = "ticket_id")
    val ticketId: Long?,

    @ColumnInfo(name = "customer_id")
    val customerId: Long?,

    val status: String,

    /** Cents. 1234 = $12.34. */
    val subtotal: Long = 0L,

    /** Cents. */
    val discount: Long = 0L,

    /** Cents. */
    @ColumnInfo(name = "total_tax")
    val totalTax: Long = 0L,

    /** Cents. */
    val total: Long = 0L,

    /** Cents. */
    @ColumnInfo(name = "amount_paid")
    val amountPaid: Long = 0L,

    /** Cents. */
    @ColumnInfo(name = "amount_due")
    val amountDue: Long = 0L,

    @ColumnInfo(name = "due_on")
    val dueOn: String?,

    val notes: String?,

    @ColumnInfo(name = "created_by")
    val createdBy: Long?,

    @ColumnInfo(name = "created_at")
    val createdAt: String,

    @ColumnInfo(name = "updated_at")
    val updatedAt: String,

    @ColumnInfo(name = "customer_name")
    val customerName: String? = null,

    @ColumnInfo(name = "locally_modified")
    val locallyModified: Boolean = false,
)
