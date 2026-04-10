package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(tableName = "expenses", indices = [Index("category"), Index("date"), Index("user_id")])
data class ExpenseEntity(
    @PrimaryKey
    val id: Long,

    val category: String,

    val amount: Double = 0.0,

    val description: String? = null,

    val date: String,

    @ColumnInfo(name = "user_name")
    val userName: String? = null,

    @ColumnInfo(name = "user_id")
    val userId: Long? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: String,

    @ColumnInfo(name = "updated_at")
    val updatedAt: String,

    @ColumnInfo(name = "locally_modified")
    val locallyModified: Boolean = false,
)
