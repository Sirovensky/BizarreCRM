package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "invoices")
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

    val subtotal: Double = 0.0,

    val discount: Double = 0.0,

    @ColumnInfo(name = "total_tax")
    val totalTax: Double = 0.0,

    val total: Double = 0.0,

    @ColumnInfo(name = "amount_paid")
    val amountPaid: Double = 0.0,

    @ColumnInfo(name = "amount_due")
    val amountDue: Double = 0.0,

    @ColumnInfo(name = "due_on")
    val dueOn: String?,

    val notes: String?,

    @ColumnInfo(name = "created_by")
    val createdBy: Long?,

    @ColumnInfo(name = "created_at")
    val createdAt: String,

    @ColumnInfo(name = "updated_at")
    val updatedAt: String,

    @ColumnInfo(name = "locally_modified")
    val locallyModified: Boolean = false,
)
