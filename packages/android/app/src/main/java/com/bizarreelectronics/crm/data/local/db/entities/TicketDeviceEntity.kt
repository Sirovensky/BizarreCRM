package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "ticket_devices")
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

    val price: Double = 0.0,

    val total: Double = 0.0,

    @ColumnInfo(name = "additional_notes")
    val additionalNotes: String?,

    @ColumnInfo(name = "due_on")
    val dueOn: String?,

    @ColumnInfo(name = "pre_conditions")
    val preConditions: String?,

    @ColumnInfo(name = "post_conditions")
    val postConditions: String?,
)
