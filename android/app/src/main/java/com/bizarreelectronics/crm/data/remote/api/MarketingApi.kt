package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.QueryMap

// ─── Campaign DTOs ────────────────────────────────────────────────────────────

/**
 * A marketing campaign row returned by GET /campaigns or GET /campaigns/:id.
 *
 * Server source: packages/server/src/routes/campaigns.routes.ts
 * Table: marketing_campaigns
 *
 * Status values: "draft" | "active" | "paused" | "archived"
 * Type values:   "birthday" | "winback" | "review_request" | "churn_warning" |
 *                "service_subscription" | "custom"
 * Channel:       "sms" | "email" | "both"
 */
data class CampaignDto(
    val id: Long,
    val name: String,
    val type: String,
    @SerializedName("segment_id")   val segmentId: Long? = null,
    val channel: String,
    @SerializedName("template_subject") val templateSubject: String? = null,
    @SerializedName("template_body")    val templateBody: String,
    @SerializedName("trigger_rule_json") val triggerRuleJson: String? = null,
    val status: String,
    @SerializedName("sent_count")      val sentCount: Int = 0,
    @SerializedName("replied_count")   val repliedCount: Int = 0,
    @SerializedName("converted_count") val convertedCount: Int = 0,
    @SerializedName("created_at")      val createdAt: String? = null,
    @SerializedName("last_run_at")     val lastRunAt: String? = null,
)

data class CreateCampaignRequest(
    val name: String,
    val type: String,
    val channel: String,
    @SerializedName("template_body")    val templateBody: String,
    @SerializedName("template_subject") val templateSubject: String? = null,
    @SerializedName("segment_id")       val segmentId: Long? = null,
    @SerializedName("trigger_rule_json") val triggerRuleJson: String? = null,
)

data class CampaignStatsData(
    val campaign: CampaignDto,
    val counts: Map<String, @JvmSuppressWildcards Int>,
)

data class CampaignPreviewData(
    @SerializedName("campaign_id")       val campaignId: Long,
    @SerializedName("total_recipients")  val totalRecipients: Int,
    val preview: List<@JvmSuppressWildcards Any>,
)

data class CampaignRunResult(
    val attempted: Int,
    val sent: Int,
    val failed: Int,
    val skipped: Int,
)

// ─── Segment DTOs ─────────────────────────────────────────────────────────────

/**
 * A customer segment row returned by GET /crm/segments.
 *
 * Server source: packages/server/src/routes/crm.routes.ts
 * Table: customer_segments
 */
data class SegmentDto(
    val id: Long,
    val name: String,
    val description: String? = null,
    @SerializedName("rule_json")     val ruleJson: String? = null,
    @SerializedName("is_auto")       val isAuto: Int = 0,
    @SerializedName("member_count")  val memberCount: Int = 0,
    @SerializedName("created_at")    val createdAt: String? = null,
    @SerializedName("updated_at")    val updatedAt: String? = null,
)

data class CreateSegmentRequest(
    val name: String,
    val description: String? = null,
    @SerializedName("rule_json") val ruleJson: String? = null,
)

// ─── API interfaces ───────────────────────────────────────────────────────────

/**
 * Campaign CRUD + dispatch endpoints.
 *
 * Server: GET/POST /campaigns, GET/PATCH/DELETE /campaigns/:id,
 *         POST /campaigns/:id/preview, POST /campaigns/:id/run-now,
 *         GET  /campaigns/:id/stats
 *
 * All endpoints are admin-only on the server; the app should only show this
 * surface to admin-role users. 404 responses are tolerated — callers show
 * an "unavailable" state rather than crashing.
 *
 * Plan §37 (ActionPlan.md lines 3255-3360).
 */
interface MarketingApi {

    // ── Campaign list ─────────────────────────────────────────────────────────

    @GET("campaigns")
    suspend fun getCampaigns(
        @QueryMap params: Map<String, String> = emptyMap(),
    ): ApiResponse<List<@JvmSuppressWildcards CampaignDto>>

    // ── Campaign CRUD ─────────────────────────────────────────────────────────

    @GET("campaigns/{id}")
    suspend fun getCampaign(
        @Path("id") id: Long,
    ): ApiResponse<CampaignDto>

    @POST("campaigns")
    suspend fun createCampaign(
        @Body request: CreateCampaignRequest,
    ): ApiResponse<CampaignDto>

    @PATCH("campaigns/{id}")
    suspend fun patchCampaign(
        @Path("id") id: Long,
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<CampaignDto>

    @DELETE("campaigns/{id}")
    suspend fun deleteCampaign(
        @Path("id") id: Long,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── Campaign actions ──────────────────────────────────────────────────────

    /**
     * Dry-run: returns total_recipients count + 3 sample rendered messages.
     * POST /campaigns/:id/preview
     */
    @POST("campaigns/{id}/preview")
    suspend fun previewCampaign(
        @Path("id") id: Long,
    ): ApiResponse<CampaignPreviewData>

    /**
     * Dispatch campaign to all eligible recipients now.
     * POST /campaigns/:id/run-now
     * Rate-limited server-side: 3 dispatches/minute per user.
     */
    @POST("campaigns/{id}/run-now")
    suspend fun runCampaignNow(
        @Path("id") id: Long,
    ): ApiResponse<CampaignRunResult>

    /**
     * Per-campaign send metrics.
     * GET /campaigns/:id/stats  → { campaign, counts: { sent, failed, replied, converted } }
     */
    @GET("campaigns/{id}/stats")
    suspend fun getCampaignStats(
        @Path("id") id: Long,
    ): ApiResponse<CampaignStatsData>
}

/**
 * Customer segment CRUD endpoints.
 *
 * Server: GET/POST /crm/segments, GET/PATCH/DELETE /crm/segments/:id,
 *         POST /crm/segments/:id/refresh
 *
 * Plan §37.3 (ActionPlan.md lines ~3285-3295).
 */
interface SegmentApi {

    @GET("crm/segments")
    suspend fun getSegments(): ApiResponse<List<@JvmSuppressWildcards SegmentDto>>

    @GET("crm/segments/{id}")
    suspend fun getSegment(
        @Path("id") id: Long,
    ): ApiResponse<SegmentDto>

    @POST("crm/segments")
    suspend fun createSegment(
        @Body request: CreateSegmentRequest,
    ): ApiResponse<SegmentDto>

    @PATCH("crm/segments/{id}")
    suspend fun patchSegment(
        @Path("id") id: Long,
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<SegmentDto>

    @DELETE("crm/segments/{id}")
    suspend fun deleteSegment(
        @Path("id") id: Long,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    /** Re-evaluate segment membership server-side. */
    @POST("crm/segments/{id}/refresh")
    suspend fun refreshSegment(
        @Path("id") id: Long,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>
}
