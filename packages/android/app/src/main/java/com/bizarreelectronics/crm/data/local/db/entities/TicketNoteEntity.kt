package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Ticket note (sub-row of a ticket). `ticket_id` references [TicketEntity.id] with
 * CASCADE delete — when the parent ticket is deleted the notes go with it.
 */
@Entity(
    tableName = "ticket_notes",
    foreignKeys = [
        ForeignKey(
            entity = TicketEntity::class,
            parentColumns = ["id"],
            childColumns = ["ticket_id"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [
        Index("ticket_id"),
    ],
)
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
