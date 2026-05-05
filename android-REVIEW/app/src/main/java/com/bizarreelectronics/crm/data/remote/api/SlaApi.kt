package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

// ─── DTOs ────────────────────────────────────────────────────────────────────

/**
 * SLA definition for a service type. Fetched from GET /sla-definitions.
 *
 * Time values are in minutes. Absent / null means "no SLA defined for this phase".
 */
data class SlaDefinitionDto(
    val id: Long = 0,
    @SerializedName("service_type")
    val serviceType: String,
    @SerializedName("diagnose_minutes")
    val diagnoseMinutes: Int?,
    @SerializedName("repair_minutes")
    val repairMinutes: Int?,
    @SerializedName("sms_minutes")
    val smsMinutes: Int?,
)

data class SlaExtendRequest(
    val reason: String,
    /** Additional minutes to add to the repair-phase deadline. */
    @SerializedName("extend_minutes")
    val extendMinutes: Int,
)

data class SlaExtendResponse(
    @SerializedName("new_deadline_ms")
    val newDeadlineMs: Long?,
    val message: String?,
)

/**
 * Aggregated SLA stats used by [SlaHeatmapScreen].
 *
 * Server returns one row per ticket with projected breach time.
 */
data class SlaHeatmapRow(
    @SerializedName("ticket_id")
    val ticketId: Long,
    @SerializedName("ticket_order_id")
    val ticketOrderId: String?,
    @SerializedName("customer_name")
    val customerName: String?,
    @SerializedName("assignee")
    val assignee: String?,
    @SerializedName("service_type")
    val serviceType: String?,
    /** Epoch ms when the ticket is projected to breach SLA. Null = already breached. */
    @SerializedName("projected_breach_ms")
    val projectedBreachMs: Long?,
    /** Remaining % of SLA budget (0..100). Negative = breached. */
    @SerializedName("remaining_pct")
    val remainingPct: Int,
    /** Absolute epoch ms of the SLA deadline. */
    @SerializedName("deadline_ms")
    val deadlineMs: Long?,
)

data class SlaHeatmapData(
    val rows: List<SlaHeatmapRow>,
)

// ─── Interface ────────────────────────────────────────────────────────────────

/**
 * §4.19 L825-L835 — SLA tracking API.
 *
 * All endpoints tolerate 404 — Android degrades gracefully when the server
 * predates the SLA module.
 *
 * ### Push notifications
 * Breach alerts are fired server-side and delivered to the device via FCM.
 * Android listens in [FcmService] — no polling required here.
 *
 * ### Customer commitment
 * Server pushes deadline info to the customer tracking page (§55).
 * Android does not need to call a separate endpoint for this.
 */
interface SlaApi {

    /**
     * Fetch SLA definitions for all (or one) service types.
     *
     * GET /sla-definitions[?service_type=<type>]
     */
    @GET("sla-definitions")
    suspend fun getDefinitions(
        @Query("service_type") serviceType: String? = null,
    ): ApiResponse<List<SlaDefinitionDto>>

    /**
     * Manager-only: extend a ticket's SLA deadline with a mandatory reason.
     *
     * POST /tickets/:id/sla-extend
     * 404 tolerated — UI hides the button when the server predates this endpoint.
     */
    @POST("tickets/{id}/sla-extend")
    suspend fun extendSla(
        @Path("id") ticketId: Long,
        @Body request: SlaExtendRequest,
    ): ApiResponse<SlaExtendResponse>

    /**
     * Aggregated heatmap data for the manager SLA visualizer.
     *
     * GET /sla/heatmap — returns all open tickets with remaining % + breach projection.
     * 404 tolerated — SlaHeatmapScreen shows empty state.
     */
    @GET("sla/heatmap")
    suspend fun getHeatmap(): ApiResponse<SlaHeatmapData>
}
