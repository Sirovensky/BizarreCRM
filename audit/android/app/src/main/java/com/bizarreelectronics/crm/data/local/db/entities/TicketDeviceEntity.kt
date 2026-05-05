package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.compose.runtime.Immutable

/**
 * Ticket device (sub-row of a ticket). Money columns stored as **Long cents**.
 *
 * `ticket_id` references [TicketEntity.id] with CASCADE delete — when the parent
 * ticket is deleted the device rows are removed automatically.
 */
@Entity(
    tableName = "ticket_devices",
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
@Immutable
data class TicketDeviceEntity(
    @PrimaryKey
    val id: Long,

    @ColumnInfo(name = "ticket_id")
    val ticketId: Long,

    @ColumnInfo(name = "device_name")
    val deviceName: String?,

    @ColumnInfo(name = "device_type")
    val deviceType: String?,

    val imei: String?,

    val serial: String?,

    @ColumnInfo(name = "security_code")
    val securityCode: String?,

    @ColumnInfo(name = "status_id")
    val statusId: Long?,

    @ColumnInfo(name = "status_name")
    val statusName: String?,

    @ColumnInfo(name = "service_name")
    val serviceName: String?,

    /** Cents. */
    val price: Long = 0L,

    /** Cents. */
    val total: Long = 0L,

    @ColumnInfo(name = "additional_notes")
    val additionalNotes: String?,

    @ColumnInfo(name = "due_on")
    val dueOn: String?,

    @ColumnInfo(name = "pre_conditions")
    val preConditions: String?,

    @ColumnInfo(name = "post_conditions")
    val postConditions: String?,
)
