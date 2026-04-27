package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

// ─── §59 Field-Service / Dispatch DTOs ───────────────────────────────────────

/**
 * List wrapper returned by GET /dispatch/jobs.
 *
 * Server: packages/server/src/routes/dispatch.ts (not yet deployed).
 * Shape: { success: true, data: { jobs: [...] } }
 */
data class DispatchJobListData(
    val jobs: List<DispatchJob>,
) {
    /**
     * A single field-service job entry.
     *
     * Status values: `scheduled | en_route | on_site | completed | cancelled`.
     * Money fields use cents (Long) to avoid floating-point rounding errors.
     */
    data class DispatchJob(
        val id: Long,
        /** Ticket order ID (e.g. "T-042") for display purposes. */
        @SerializedName("order_id")
        val orderId: String?,
        /** Short human-readable description of the job / service. */
        val description: String?,
        /** Customer full name. */
        @SerializedName("customer_name")
        val customerName: String?,
        /** Customer phone for one-tap dialling. */
        @SerializedName("customer_phone")
        val customerPhone: String?,
        /** Full street address for Google Maps intent. */
        val address: String?,
        /** Latitude in decimal degrees (null = no geo on record). */
        val latitude: Double?,
        /** Longitude in decimal degrees (null = no geo on record). */
        val longitude: Double?,
        /**
         * Current job status.
         * Values: `scheduled | en_route | on_site | completed | cancelled`.
         */
        val status: String?,
        /**
         * Scheduled start time (ISO-8601 string).
         * Display using [java.time.Instant.parse] + locale format.
         */
        @SerializedName("scheduled_at")
        val scheduledAt: String?,
        /** Estimated drive time in minutes from the tech's last known location. */
        @SerializedName("eta_minutes")
        val etaMinutes: Int?,
        /**
         * Job priority: 1 (highest) to 5 (lowest).
         * Used for list ranking in §59.1.
         */
        val priority: Int?,
        /** Tech-visible notes attached to this job. */
        val notes: String?,
        /** Invoice total in US cents. Null = not yet invoiced. */
        @SerializedName("total_cents")
        val totalCents: Long?,
        @SerializedName("created_at")
        val createdAt: String?,
        @SerializedName("updated_at")
        val updatedAt: String?,
    )
}

/**
 * Response body for POST /dispatch/optimize (§59.2).
 *
 * Server returns an ordered list of job IDs representing the optimal
 * route order for the technician's day.
 */
data class OptimizeRouteResponse(
    /** Ordered list of dispatch job IDs (optimal route sequence). */
    @SerializedName("job_ids")
    val jobIds: List<Long>,
    /**
     * Total estimated drive time in minutes for the optimized route.
     * Null when the server cannot calculate (e.g. missing coordinates).
     */
    @SerializedName("total_eta_minutes")
    val totalEtaMinutes: Int?,
)

/**
 * Request body for PATCH /dispatch/jobs/:id.
 *
 * All fields are nullable — send only what needs to change.
 * Status values: `scheduled | en_route | on_site | completed | cancelled`.
 */
data class UpdateDispatchJobRequest(
    /** Updated job status. */
    val status: String? = null,
    /** Technician notes to append / overwrite. */
    val notes: String? = null,
)
