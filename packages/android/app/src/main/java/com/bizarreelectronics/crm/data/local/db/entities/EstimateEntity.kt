package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(tableName = "estimates", indices = [Index("customer_id"), Index("status"), Index("created_at")])
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

    val discount: Double = 0.0,

    val notes: String? = null,

    @ColumnInfo(name = "valid_until")
    val validUntil: String? = null,

    val subtotal: Double = 0.0,

    @ColumnInfo(name = "total_tax")
    val totalTax: Double = 0.0,

    val total: Double = 0.0,

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
