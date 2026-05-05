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
 * Single row from GET /tickets/warranty-lookup.
 *
 * The server computes [warrantyActive] by comparing [warrantyExpires] with today.
 * [warrantyExpires] is ISO-8601 date string (YYYY-MM-DD).
 */
data class WarrantyLookupRowDto(
    @SerializedName("ticket_id")
    val ticketId: Long,
    @SerializedName("order_id")
    val orderId: String?,
    @SerializedName("device_name")
    val deviceName: String?,
    val imei: String?,
    val serial: String?,
    @SerializedName("warranty_days")
    val warrantyDays: Int,
    @SerializedName("warranty_expires")
    val warrantyExpires: String?,
    @SerializedName("warranty_active")
    val warrantyActive: Boolean,
    @SerializedName("status_name")
    val statusName: String?,
    @SerializedName("customer_first")
    val customerFirst: String?,
    @SerializedName("customer_last")
    val customerLast: String?,
    @SerializedName("ticket_created")
    val ticketCreated: String?,
    @SerializedName("diagnostic_notes")
    val diagnosticNotes: List<DiagnosticNoteDto>? = null,
)

data class DiagnosticNoteDto(
    val content: String?,
    @SerializedName("created_at")
    val createdAt: String?,
)

/**
 * Single row from GET /tickets/device-history.
 */
data class DeviceHistoryRowDto(
    val id: Long,
    @SerializedName("order_id")
    val orderId: String?,
    @SerializedName("created_at")
    val createdAt: String?,
    @SerializedName("updated_at")
    val updatedAt: String?,
    @SerializedName("device_name")
    val deviceName: String?,
    val imei: String?,
    val serial: String?,
    @SerializedName("device_type")
    val deviceType: String?,
    @SerializedName("status_name")
    val statusName: String?,
    @SerializedName("status_color")
    val statusColor: String?,
    @SerializedName("status_is_closed")
    val statusIsClosed: Int?,
    @SerializedName("customer_first")
    val customerFirst: String?,
    @SerializedName("customer_last")
    val customerLast: String?,
)

/**
 * Full warranty record returned by POST /warranties and GET /warranties/search.
 *
 * [eligible] is computed server-side from [installDate], [duration], and [conditions].
 */
data class WarrantyRecordDto(
    val id: Long = 0,
    @SerializedName("part_id")
    val partId: Long?,
    val serial: String?,
    @SerializedName("install_date")
    val installDate: String?,
    /** "90d" | "1yr" | "lifetime" */
    val duration: String,
    val conditions: String?,
    val eligible: Boolean,
    @SerializedName("ticket_id")
    val ticketId: Long?,
    @SerializedName("customer_name")
    val customerName: String?,
    val imei: String?,
    @SerializedName("receipt_number")
    val receiptNumber: String?,
    @SerializedName("cost_center")
    val costCenter: String,
    @SerializedName("created_at")
    val createdAt: String? = null,
)

data class CreateWarrantyRequest(
    @SerializedName("ticket_id")
    val ticketId: Long,
    @SerializedName("part_id")
    val partId: Long?,
    val serial: String?,
    val duration: String,
    val conditions: String?,
    @SerializedName("cost_center")
    val costCenter: String,
)

data class WarrantyClaimRequest(
    @SerializedName("warranty_id")
    val warrantyId: Long,
    val notes: String?,
    /** "within" | "out" | "manual" — caller may pre-compute; server always validates. */
    val branch: String?,
)

data class WarrantyClaimResponse(
    /** "within" | "out" | "manual" */
    val branch: String,
    @SerializedName("new_ticket_id")
    val newTicketId: Long?,
    val message: String?,
)

data class WarrantySearchData(
    val warranties: List<WarrantyRecordDto>,
)

// ─── Interface ────────────────────────────────────────────────────────────────

/**
 * §4.18 L812-L822 — Warranty tracking API.
 *
 * All endpoints tolerate 404 — callers degrade gracefully when server predates
 * the warranty module.
 *
 * ### Decision branching (POST /warranties/:id/claim)
 * - within  → zero-price "Warranty Return" ticket created; [WarrantyClaimResponse.newTicketId] set.
 * - out     → standard "Paid Repair" ticket; [WarrantyClaimResponse.newTicketId] set.
 * - manual  → no ticket created; tech receives [WarrantyClaimResponse.message] with next steps.
 *
 * ### Auto-SMS
 * The server fires an SMS confirmation (via the BizarreSMS queue) when a claim
 * is accepted. Android does not need to trigger this separately.
 *
 * ### Reporting
 * [getClaimRateDashboard] returns stub metrics for §15 reporting screen ("Warranty
 * claim rate by supplier / tech"). 404 is tolerated — the reports screen silently
 * omits the tile.
 */
interface WarrantyApi {

    /**
     * Auto-create a warranty record when a ticket is closed (called server-side
     * and also available for manual creation from the app).
     *
     * POST /warranties
     */
    @POST("warranties")
    suspend fun createWarranty(
        @Body request: CreateWarrantyRequest,
    ): ApiResponse<WarrantyRecordDto>

    /**
     * Search warranty records by IMEI, receipt number, or customer name.
     *
     * GET /warranties/search?imei=|receipt=|name=
     */
    @GET("warranties/search")
    suspend fun searchWarranties(
        @Query("imei") imei: String? = null,
        @Query("receipt") receipt: String? = null,
        @Query("name") name: String? = null,
    ): ApiResponse<WarrantySearchData>

    /**
     * File a warranty claim against an existing warranty record.
     *
     * POST /warranties/:id/claim
     *
     * Returns [WarrantyClaimResponse] with [branch] ("within"|"out"|"manual") and
     * optionally the [newTicketId] of the follow-up ticket created by the server.
     */
    @POST("warranties/{id}/claim")
    suspend fun fileClaim(
        @Path("id") warrantyId: Long,
        @Body request: WarrantyClaimRequest,
    ): ApiResponse<WarrantyClaimResponse>

    /**
     * Stub dashboard metric for §15 reporting: "Warranty claim rate by supplier/tech".
     *
     * GET /warranties/claim-rate-dashboard
     * 404 tolerated — reports screen omits the tile silently.
     */
    @GET("warranties/claim-rate-dashboard")
    suspend fun getClaimRateDashboard(): ApiResponse<@JvmSuppressWildcards Map<String, Any>>

    // ─── §46 Ticket-level warranty & device-history lookup ────────────────────

    /**
     * Check if a device is under warranty.
     *
     * GET /tickets/warranty-lookup?imei=|serial=|phone=
     *
     * Returns up to 20 records with [WarrantyLookupRowDto.warrantyActive] computed
     * server-side. At least one of [imei], [serial], or [phone] must be non-null.
     */
    @GET("tickets/warranty-lookup")
    suspend fun warrantyLookup(
        @Query("imei") imei: String? = null,
        @Query("serial") serial: String? = null,
        @Query("phone") phone: String? = null,
    ): ApiResponse<List<WarrantyLookupRowDto>>

    /**
     * List all past tickets for a given IMEI or serial number.
     *
     * GET /tickets/device-history?imei=|serial=
     *
     * Returns up to 50 records ordered by [DeviceHistoryRowDto.createdAt] desc.
     * At least one of [imei] or [serial] must be non-null.
     */
    @GET("tickets/device-history")
    suspend fun deviceHistory(
        @Query("imei") imei: String? = null,
        @Query("serial") serial: String? = null,
    ): ApiResponse<List<DeviceHistoryRowDto>>
}
