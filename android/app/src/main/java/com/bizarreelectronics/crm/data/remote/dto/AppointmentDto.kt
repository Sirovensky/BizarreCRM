package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

data class AppointmentItem(
    val id: Long,
    val title: String?,
    @SerializedName("customer_name")
    val customerName: String?,
    @SerializedName("customer_id")
    val customerId: Long?,
    @SerializedName("employee_id")
    val employeeId: Long?,
    @SerializedName("employee_name")
    val employeeName: String?,
    @SerializedName("start_time")
    val startTime: String?,           // ISO-8601
    @SerializedName("end_time")
    val endTime: String?,
    @SerializedName("duration_minutes")
    val durationMinutes: Int?,
    val status: String?,              // scheduled | confirmed | cancelled | no_show | completed
    val type: String?,
    val location: String?,
    val notes: String?,
    @SerializedName("reminder_offset_minutes")
    val reminderOffsetMinutes: Int?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
)
