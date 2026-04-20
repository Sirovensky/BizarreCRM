package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.compose.runtime.Immutable

/**
 * Estimate row. Money columns stored as **Long cents**.
 */
@Entity(
    tableName = "estimates",
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
        Index("status"),
        Index("created_at"),
    ],
)
@Immutable
data class EstimateEntity(
    @PrimaryKey
    val id: Long,

    @ColumnInfo(name = "order_id")
    val orderId: String,

    @ColumnInfo(name = "customer_id")
    val customerId: Long? = null,

    @ColumnInfo(name = "customer_name")
    val customerName: String? = null,

    val status: String,

    /** Cents. */
    val discount: Long = 0L,

    val notes: String? = null,

    @ColumnInfo(name = "valid_until")
    val validUntil: String? = null,

    /** Cents. */
    val subtotal: Long = 0L,

    /** Cents. */
    @ColumnInfo(name = "total_tax")
    val totalTax: Long = 0L,

    /** Cents. */
    val total: Long = 0L,

    @ColumnInfo(name = "converted_ticket_id")
    val convertedTicketId: Long? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: String,

    @ColumnInfo(name = "updated_at")
    val updatedAt: String,

    @ColumnInfo(name = "is_deleted")
    val isDeleted: Boolean = false,

    @ColumnInfo(name = "locally_modified")
    val locallyModified: Boolean = false,
)
