package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "ticket_notes")
data class TicketNoteEntity(
    @PrimaryKey
    val id: Long,

    @ColumnInfo(name = "ticket_id")
    val ticketId: Long,

    @ColumnInfo(name = "user_id")
    val userId: Long,

    @ColumnInfo(name = "user_name")
    val userName: String?,

    val type: String,

    val content: String,

    @ColumnInfo(name = "is_flagged")
    val isFlagged: Boolean = false,

    @ColumnInfo(name = "created_at")
    val createdAt: String,
)
