package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path

// ─── Campaign DTOs ────────────────────────────────────────────────────────────

/**
 * Campaign status values (server-enforced CHECK constraint).
 * "draft" | "active" | "paused" | "archived"
 */
data class Campaign(
    val id: Long,
    val name: String,
    val type: String,              // "birthday"|"winback"|"review_request"|"churn_warning"|"service_subscription"|"custom"
    @SerializedName("segment_id")    val segmentId: Long?,
    val channel: String,           // "sms" | "email" | "both"
    @SerializedName("template_subject") val templateSubject: String?,
    @SerializedName("template_body")    val templateBody: String,
    @SerializedName("trigger_rule_json") val triggerRuleJson: String?,
    val status: String,            // "draft" | "active" | "paused" | "archived"
    @SerializedName("sent_count")       val sentCount: Int = 0,
    @SerializedName("replied_count")    val repliedCount: Int = 0,
    @SerializedName("converted_count")  val convertedCount: Int = 0,
    @SerializedName("created_at")       val createdAt: String?,
    @SerializedName("last_run_at")      val lastRunAt: String?,
)

data class CampaignListData(val campaigns: List<Campaign>? = null)

/**
 * The GET /campaigns response returns the list directly (not wrapped in a
 * named field — the route does `res.json({ success:true, data: rows })`).
 * Use [CampaignRawListData] for that endpoint.
 */
typealias CampaignRawListData = List<Campaign>

data class CreateCampaignRequest(
    val name: String,
    val type: String,
    val channel: String,
    @SerializedName("template_body")    val templateBody: String,
    @SerializedName("template_subject") val templateSubject: String? = null,
    @SerializedName("segment_id")       val segmentId: Long? = null,
    @SerializedName("trigger_rule_json") val triggerRuleJson: String? = null,
)

data class UpdateCampaignRequest(
    val name: String? = null,
    val channel: String? = null,
    val status: String? = null,
    @SerializedName("template_subject") val templateSubject: String? = null,
    @SerializedName("template_body")    val templateBody: String? = null,
    @SerializedName("segment_id")       val segmentId: Long? = null,
    @SerializedName("trigger_rule_json") val triggerRuleJson: String? = null,
)

data class CampaignData(val campaign: Campaign? = null)

// ─── Campaign stats DTOs ──────────────────────────────────────────────────────

data class CampaignCounts(
    val sent: Int = 0,
    val failed: Int = 0,
    val replied: Int = 0,
    val converted: Int = 0,
)

data class CampaignStatsData(
    val campaign: Campaign,
    val counts: CampaignCounts,
)

// ─── Preview DTOs ─────────────────────────────────────────────────────────────

data class PreviewRecipient(
    @SerializedName("customer_id")    val customerId: Long,
    @SerializedName("first_name")     val firstName: String?,
    @SerializedName("rendered_body")  val renderedBody: String,
)

data class CampaignPreviewData(
    @SerializedName("campaign_id")        val campaignId: Long,
    @SerializedName("total_recipients")   val totalRecipients: Int,
    val preview: List<PreviewRecipient>,
)

// ─── Run-now result DTOs ──────────────────────────────────────────────────────

data class DispatchResult(
    val attempted: Int,
    val sent: Int,
    val failed: Int,
    val skipped: Int,
)

// ─── Segment DTOs ─────────────────────────────────────────────────────────────

data class CustomerSegment(
    val id: Long,
    val name: String,
    val description: String?,
    @SerializedName("rule_json")         val ruleJson: String,
    @SerializedName("is_auto")           val isAuto: Int = 1,
    @SerializedName("last_refreshed_at") val lastRefreshedAt: String?,
    @SerializedName("member_count")      val memberCount: Int = 0,
    @SerializedName("created_at")        val createdAt: String?,
)

data class SegmentListData(val segments: List<CustomerSegment>? = null)

/**
 * GET /crm/segments returns the list directly (same raw-list pattern as campaigns).
 */
typealias SegmentRawListData = List<CustomerSegment>

data class CreateSegmentRequest(
    val name: String,
    val description: String? = null,
    @SerializedName("rule_json") val ruleJson: String,
    @SerializedName("is_auto")   val isAuto: Int = 0,
)

data class SegmentData(val segment: CustomerSegment? = null)

data class SegmentMember(
    val id: Long,
    @SerializedName("first_name") val firstName: String?,
    @SerializedName("last_name")  val lastName: String?,
    val email: String?,
    val phone: String?,
)

data class SegmentMembersData(
    val members: List<SegmentMember>,
    val total: Int,
)

// ─── Review-request trigger DTOs ──────────────────────────────────────────────

data class ReviewRequestTriggerRequest(
    @SerializedName("ticket_id") val ticketId: Long,
)

// ─── API interface ────────────────────────────────────────────────────────────

/**
 * Marketing & Growth endpoints.
 *
 * Campaign CRUD at [GET/POST] /api/v1/campaigns.
 * Segment CRUD at [GET/POST] /api/v1/crm/segments.
 *
 * 404-tolerant — callers catch [retrofit2.HttpException] with code 404 and
 * show "Not available on this server" rather than crashing.
 *
 * Plan §37 ActionPlan.md L2959-L3000.
 */
interface MarketingApi {

    // ── Campaign list ─────────────────────────────────────────────────────────

    /** List all campaigns ordered by created_at DESC (§37.1). */
    @GET("campaigns")
    suspend fun getCampaigns(): ApiResponse<CampaignRawListData>

    /** Get a single campaign by id (§37.1). */
    @GET("campaigns/{id}")
    suspend fun getCampaign(@Path("id") id: Long): ApiResponse<Campaign>

    /** Create a new campaign in draft status (§37.2). */
    @POST("campaigns")
    suspend fun createCampaign(@Body request: CreateCampaignRequest): ApiResponse<Campaign>

    /** Update a campaign's fields (§37.2). */
    @PATCH("campaigns/{id}")
    suspend fun updateCampaign(
        @Path("id") id: Long,
        @Body request: UpdateCampaignRequest,
    ): ApiResponse<Campaign>

    /** Archive / delete a campaign (§37.2). */
    @DELETE("campaigns/{id}")
    suspend fun deleteCampaign(@Path("id") id: Long): ApiResponse<Map<String, Long>>

    /** Preview recipients + rendered messages (§37.2). */
    @POST("campaigns/{id}/preview")
    suspend fun previewCampaign(@Path("id") id: Long): ApiResponse<CampaignPreviewData>

    /** Dispatch a campaign immediately to all eligible recipients (§37.2). */
    @POST("campaigns/{id}/run-now")
    suspend fun runCampaignNow(@Path("id") id: Long): ApiResponse<DispatchResult>

    /** Get sent/replied/converted stats for a campaign (§37.1). */
    @GET("campaigns/{id}/stats")
    suspend fun getCampaignStats(@Path("id") id: Long): ApiResponse<CampaignStatsData>

    // ── Segments ──────────────────────────────────────────────────────────────

    /** List all customer segments (§37.3). */
    @GET("crm/segments")
    suspend fun getSegments(): ApiResponse<SegmentRawListData>

    /** Create a new segment (§37.3). */
    @POST("crm/segments")
    suspend fun createSegment(@Body request: CreateSegmentRequest): ApiResponse<CustomerSegment>

    /** Refresh segment membership (re-evaluate rule) (§37.3). */
    @POST("crm/segments/{id}/refresh")
    suspend fun refreshSegment(@Path("id") id: Long): ApiResponse<CustomerSegment>

    /** List segment members with pagination (§37.3 size preview). */
    @GET("crm/segments/{id}/members")
    suspend fun getSegmentMembers(@Path("id") id: Long): ApiResponse<SegmentMembersData>

    // ── Review solicitation ───────────────────────────────────────────────────

    /**
     * Trigger a review-request SMS for a closed ticket (§37.5).
     * Requires an active `review_request` campaign; server no-ops gracefully
     * if none exists.
     */
    @POST("campaigns/review-request/trigger")
    suspend fun triggerReviewRequest(
        @Body request: ReviewRequestTriggerRequest,
    ): ApiResponse<DispatchResult>
}
