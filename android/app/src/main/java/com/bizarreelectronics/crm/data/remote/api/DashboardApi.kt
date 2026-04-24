package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.ui.screens.dashboard.components.ActivityItem
import com.bizarreelectronics.crm.ui.screens.dashboard.components.AnnouncementDto
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * §3.3 L513 — Dashboard-specific API operations.
 *
 * Dismiss endpoint: POST /dashboard/attention/{id}/dismiss
 *
 * **Graceful degradation**: the server does not yet implement these endpoints.
 * The ViewModel catches HTTP 404 and falls back to local preferences for all
 * operations so the UI degrades gracefully regardless of server status.
 *
 * Response body when endpoints are live:
 * ```json
 * { "success": true, "data": { ... } }
 * ```
 */
interface DashboardApi {

    /**
     * Server-side dismiss for a needs-attention item.
     *
     * Returns a generic [ApiResponse] with a map payload. The ViewModel treats
     * any non-exception response (including 204 No Content projected through
     * Retrofit) as success. A [retrofit2.HttpException] with code 404 is caught
     * and silently demoted to the local-only fallback path.
     *
     * @param id [NeedsAttentionItem.id] value as assigned by the server.
     */
    @POST("dashboard/attention/{id}/dismiss")
    suspend fun dismissAttentionItem(
        @Path("id") id: String,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    /**
     * §3.6 L534 — Fetch recent CRM activity for the Activity Feed card.
     *
     * Endpoint: GET /activity?limit=20
     *
     * **Graceful degradation**: 404 means the server does not yet expose this
     * endpoint. The ViewModel catches [retrofit2.HttpException] with code 404 and
     * emits an empty list so [ActivityFeedCard] shows its empty state.
     *
     * Response shape (when live):
     * ```json
     * { "success": true, "data": { "items": [ { "id", "actor", "verb", "subject",
     *   "time_ago", "avatar_initials" }, ... ] } }
     * ```
     *
     * @param limit Maximum number of activity entries to return. Default 20.
     */
    @GET("activity")
    suspend fun recentActivity(
        @Query("limit") limit: Int = 20,
    ): ApiResponse<ActivityFeedData>

    /**
     * §3.7 L538 — Fetch the currently active announcement.
     *
     * Endpoint: GET /announcements/current
     *
     * **Graceful degradation**: 404 means no active announcement (or the endpoint
     * is not yet implemented). The ViewModel catches 404 and emits `null`.
     *
     * Response shape (when live):
     * ```json
     * { "success": true, "data": { "id", "title", "body", "learn_more_url" } }
     * ```
     */
    @GET("announcements/current")
    suspend fun currentAnnouncement(): ApiResponse<AnnouncementDto>
}

/**
 * §3.6 — Wrapper around the activity list returned by `GET /activity`.
 */
data class ActivityFeedData(
    val items: List<ActivityItem> = emptyList(),
)
