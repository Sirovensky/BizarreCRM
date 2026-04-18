package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.compose.runtime.Immutable

@Entity(tableName = "ticket_statuses")
@Immutable
data class TicketStatusEntity(
    @PrimaryKey
    val id: Long,

    val name: String,

    val color: String,

    @ColumnInfo(name = "sort_order")
    val sortOrder: Int = 0,

    @ColumnInfo(name = "is_closed")
    val isClosed: Boolean = false,

    @ColumnInfo(name = "is_cancelled")
    val isCancelled: Boolean = false,

    @ColumnInfo(name = "notify_customer")
    val notifyCustomer: Boolean = false,
)
