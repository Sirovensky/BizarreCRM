package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.compose.runtime.Immutable

@Entity(tableName = "notifications")
@Immutable
data class NotificationEntity(
    @PrimaryKey
    val id: Long,

    @ColumnInfo(name = "user_id")
    val userId: Long,

    val type: String,

    val title: String,

    val message: String,

    @ColumnInfo(name = "entity_type")
    val entityType: String?,

    @ColumnInfo(name = "entity_id")
    val entityId: Long?,

    @ColumnInfo(name = "is_read")
    val isRead: Boolean = false,

    @ColumnInfo(name = "created_at")
    val createdAt: String,
)
