package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.QueryMap

// ─── DTOs ─────────────────────────────────────────────────────────────────────

/** Frequency options for a scheduled report. */
enum class ScheduleFrequency { DAILY, WEEKLY, MONTHLY }

/**
 * Tenant-level schedule spec sent to POST /reports/scheduled.
 *
 * @param reportType  e.g. "sales", "tickets", "inventory", "tax"
 * @param frequency   DAILY / WEEKLY / MONTHLY
 * @param weekday     0=Sun … 6=Sat — only used when frequency == WEEKLY
 * @param dayOfMonth  1–31 — only used when frequency == MONTHLY
 * @param recipients  comma-separated email string; empty means no email delivery
 * @param emailEnabled   deliver to [recipients] via email
 * @param inAppEnabled   create an in-app notification entry
 * @param fcmEnabled     send an FCM push to all tenant devices
 */
data class ScheduledReportSpec(
    val reportType: String,
    val frequency: ScheduleFrequency,
    val weekday: Int = 1,          // Monday
    val dayOfMonth: Int = 1,
    val recipients: String = "",
    val emailEnabled: Boolean = false,
    val inAppEnabled: Boolean = true,
    val fcmEnabled: Boolean = false,
)

/**
 * A persisted scheduled report row returned by GET /reports/scheduled.
 *
 * Fields mirror the server's JSON; unknown keys are ignored.
 */
data class ScheduledReport(
    val id: String,
    val reportType: String,
    val frequency: String,
    val weekday: Int?,
    val dayOfMonth: Int?,
    val recipients: String,
    val emailEnabled: Boolean,
    val inAppEnabled: Boolean,
    val fcmEnabled: Boolean,
    val paused: Boolean,
)

// ─── API interface ─────────────────────────────────────────────────────────────

interface ReportApi {

    @GET("reports/dashboard")
    suspend fun getDashboard(): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    @GET("reports/needs-attention")
    suspend fun getNeedsAttention(): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    @GET("reports/sales")
    suspend fun getSalesReport(
        @QueryMap filters: Map<String, String> = emptyMap()
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── §15 L1735 — tickets report (404 tolerated; stub shown when absent) ───
    @GET("reports/tickets")
    suspend fun getTicketsReport(
        @QueryMap filters: Map<String, String> = emptyMap()
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── §15 L1743 — inventory report ─────────────────────────────────────────
    @GET("reports/inventory")
    suspend fun getInventoryReport(
        @QueryMap filters: Map<String, String> = emptyMap()
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── §15 L1747 — tax report ────────────────────────────────────────────────
    @GET("reports/tax")
    suspend fun getTaxReport(
        @QueryMap filters: Map<String, String> = emptyMap()
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── §15 L1726 — scheduled reports ────────────────────────────────────────

    /** List all tenant-level schedules. 404 → tolerated as empty list. */
    @GET("reports/scheduled")
    suspend fun getScheduledReports(): ApiResponse<List<@JvmSuppressWildcards Any>>

    /** Create a new scheduled report. */
    @POST("reports/scheduled")
    suspend fun createScheduledReport(
        @Body spec: ScheduledReportSpec,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    /** Pause or resume an existing schedule. Body: `{"paused": true|false}`. */
    @PATCH("reports/scheduled/{id}")
    suspend fun patchScheduledReport(
        @Path("id") id: String,
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    /** Delete a scheduled report by id. */
    @DELETE("reports/scheduled/{id}")
    suspend fun deleteScheduledReport(
        @Path("id") id: String,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    /** Trigger an immediate run of a report type. Body: `{"reportType": "sales"}`. */
    @POST("reports/run-now")
    suspend fun runNow(
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>
}
