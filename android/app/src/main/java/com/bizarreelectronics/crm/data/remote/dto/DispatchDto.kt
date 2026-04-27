package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

// ─── List wrapper matching server { data: { jobs: [...], pagination } } ───────

data class DispatchJobListData(
    val jobs: List<DispatchJobDetail>,
    val pagination: Pagination? = null,
)

/**
 * A single field-service job row as returned by
 *   GET /api/v1/field-service/jobs
 *   GET /api/v1/field-service/jobs/:id
 *
 * Server joins customers + users so customer/tech name fields are available.
 * All nullable fields are absent when the value is NULL in SQLite.
 */
data class DispatchJobDetail(
    val id: Long,
    @SerializedName("ticket_id")
    val ticketId: Long?,
    @SerializedName("customer_id")
    val customerId: Long?,
    @SerializedName("customer_first_name")
    val customerFirstName: String?,
    @SerializedName("customer_last_name")
    val customerLastName: String?,
    @SerializedName("assigned_technician_id")
    val assignedTechnicianId: Long?,
    @SerializedName("tech_first_name")
    val techFirstName: String?,
    @SerializedName("tech_last_name")
    val techLastName: String?,
    @SerializedName("address_line")
    val addressLine: String?,
    val city: String?,
    val state: String?,
    val postcode: String?,
    val lat: Double?,
    val lng: Double?,
    @SerializedName("scheduled_window_start")
    val scheduledWindowStart: String?,
    @SerializedName("scheduled_window_end")
    val scheduledWindowEnd: String?,
    val priority: String = "normal",
    val status: String = "unassigned",
    @SerializedName("estimated_duration_minutes")
    val estimatedDurationMinutes: Int?,
    @SerializedName("actual_duration_minutes")
    val actualDurationMinutes: Int?,
    val notes: String?,
    @SerializedName("technician_notes")
    val technicianNotes: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
) {
    val customerFullName: String
        get() = listOfNotNull(customerFirstName, customerLastName).joinToString(" ").ifBlank { "Unknown customer" }

    val techFullName: String
        get() = listOfNotNull(techFirstName, techLastName).joinToString(" ").ifBlank { "Unassigned" }

    /** Human-readable single-line address. */
    val fullAddress: String
        get() = listOfNotNull(addressLine, city, state, postcode).joinToString(", ").ifBlank { "No address" }
}
