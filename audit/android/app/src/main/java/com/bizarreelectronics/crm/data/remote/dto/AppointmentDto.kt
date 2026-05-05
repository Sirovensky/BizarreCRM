package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

data class AppointmentItem(
    val id: Long,
    val title: String?,
    @SerializedName("customer_name")
    val customerName: String?,
    @SerializedName("customer_id")
    val customerId: Long?,
    @SerializedName("customer_phone")
    val customerPhone: String?,
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
    // Linked entities (10.2)
    @SerializedName("linked_ticket_id")
    val linkedTicketId: Long?,
    @SerializedName("linked_ticket_status")
    val linkedTicketStatus: String?,
    @SerializedName("linked_estimate_id")
    val linkedEstimateId: Long?,
    @SerializedName("linked_estimate_total")
    val linkedEstimateTotal: Double?,
    @SerializedName("linked_lead_id")
    val linkedLeadId: Long?,
    @SerializedName("linked_lead_stage")
    val linkedLeadStage: String?,
    // Recurrence (10.3)
    val rrule: String?,
    @SerializedName("recurrence_parent_id")
    val recurrenceParentId: Long?,
    // §10.6 check-in / check-out timestamps
    @SerializedName("checked_in_at")
    val checkedInAt: String?,
    @SerializedName("checked_out_at")
    val checkedOutAt: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
)
