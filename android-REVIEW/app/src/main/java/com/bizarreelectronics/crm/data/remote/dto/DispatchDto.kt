package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

// ─── §59.2 Route optimisation request / response ────────────────────────────

/**
 * Request body for POST /api/v1/field-service/routes/optimize.
 *
 * [technicianId] must be a positive integer user ID.
 * [routeDate]    must be YYYY-MM-DD.
 * [jobIds]       ordered list of job IDs to include in the optimisation run.
 *                The server will reorder these and return the proposed sequence.
 */
data class RouteOptimizeRequest(
    @SerializedName("technician_id") val technicianId: Long,
    @SerializedName("route_date")    val routeDate: String,
    @SerializedName("job_ids")       val jobIds: List<Long>,
)

/**
 * Response data for POST /api/v1/field-service/routes/optimize.
 *
 * Wrapped inside [ApiResponse.data] as usual.
 *
 * [proposedOrder]     job IDs in optimised visit order.
 * [totalDistanceKm]   estimated driving distance for this route (greedy heuristic).
 * [algorithm]         always "greedy-nearest-neighbor" from current server.
 * [note]              human-readable caveat from server.
 * [startFromHome]     true if tech home coords were used as route origin.
 */
data class RouteOptimizeResult(
    @SerializedName("proposed_order")     val proposedOrder: List<Long>,
    @SerializedName("total_distance_km")  val totalDistanceKm: Double,
    @SerializedName("algorithm")          val algorithm: String,
    @SerializedName("note")               val note: String,
    @SerializedName("start_from_home")    val startFromHome: Boolean,
)

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
