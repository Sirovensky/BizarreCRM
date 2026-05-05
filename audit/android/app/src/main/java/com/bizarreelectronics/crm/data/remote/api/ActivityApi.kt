package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ActivityPageResponse
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * §3.16 L592-L599 — Activity feed API.
 *
 * All endpoints tolerate 404 — caller treats it as empty / unsupported.
 *
 * Cursor-based pagination:
 *   GET /activity?limit=20             — first page (cursor absent → newest first)
 *   GET /activity?cursor=<id>&limit=20 — subsequent pages
 *   Response shape: ApiResponse<ActivityPageResponse>
 *
 * Reactions:
 *   POST /activity/{id}/reactions { emoji: "👍" }
 *   404 → silently tolerated (server predates reactions).
 *
 * SSO domain-check (§2.20 L449) lives on [AuthApi.checkSsoDomain].
 */
interface ActivityApi {

    /**
     * Fetch a page of activity events, newest first.
     *
     * @param cursor  Opaque cursor from [ActivityPageResponse.nextCursor]. Null for the first page.
     * @param limit   Page size. Typically 20.
     * @param types   Comma-separated event-type filter ("ticket,invoice"). Null = all types.
     * @param employee Username filter for myActivityOnly mode. Null = all employees.
     */
    @GET("activity")
    suspend fun getActivity(
        @Query("cursor") cursor: String? = null,
        @Query("limit") limit: Int = 20,
        @Query("types") types: String? = null,
        @Query("employee") employee: String? = null,
    ): ApiResponse<ActivityPageResponse>

    /**
     * Post a reaction emoji to a specific activity event.
     *
     * Body: { "emoji": "<emoji>" }
     * 404 → server predates the reactions endpoint; caller tolerates silently.
     */
    @POST("activity/{id}/reactions")
    suspend fun postReaction(
        @Path("id") id: Long,
        @Body body: Map<String, String>,
    ): ApiResponse<Unit>
}
