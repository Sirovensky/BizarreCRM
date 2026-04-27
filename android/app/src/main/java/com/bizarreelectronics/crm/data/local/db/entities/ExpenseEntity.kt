package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.compose.runtime.Immutable

/**
 * Expense row. `amount` is stored as **Long cents**.
 */
@Entity(tableName = "expenses", indices = [Index("category"), Index("date"), Index("user_id")])
@Immutable
data class ExpenseEntity(
    @PrimaryKey
    val id: Long,

    val category: String,

    /** Cents. 1234 = $12.34. */
    val amount: Long = 0L,

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

    /**
     * Approval status synced from the server.
     * Values: `pending` | `approved` | `denied`.
     * Mirrors the server `expenses.status` column added in server migration 120.
     * Room migration 12 → 13 adds this column with DEFAULT 'pending' so existing
     * cached rows are treated as pending until the next background sync overwrites them.
     */
    @ColumnInfo(name = "status")
    val status: String = "pending",

    @ColumnInfo(name = "locally_modified")
    val locallyModified: Boolean = false,
)
