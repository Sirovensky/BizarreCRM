package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.MorningChecklistCompleteBody
import com.bizarreelectronics.crm.data.remote.dto.MorningChecklistConfigDto
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST

/**
 * §36 L585–L588 — Retrofit interface for morning-checklist server endpoints.
 *
 * **Graceful degradation**: both endpoints are optional.  HTTP 404 means
 * the server does not yet expose them.  Call sites catch [retrofit2.HttpException]
 * with code 404 and fall back to local defaults / local-only state.
 *
 * Tenant-customizable steps contract:
 * - `GET /tenants/me/morning-checklist` returns an ordered list of steps.
 *   If the response is 404, [MorningChecklistDefaults.steps] is used instead.
 *   The server may add, remove, or reorder steps; the app renders whatever it
 *   receives without requiring a client update.
 *
 * Completion reporting:
 * - `POST /morning-checklist/complete` records the completed steps for the day.
 *   404 is silently ignored — local [AppPreferences] persistence is always the
 *   source of truth for the dashboard trigger logic.
 */
interface MorningChecklistApi {

    /**
     * Fetch the tenant-customised checklist steps.
     *
     * Endpoint: `GET /tenants/me/morning-checklist`
     *
     * 404 → caller falls back to [MorningChecklistDefaults.steps].
     *
     * Response shape (when live):
     * ```json
     * { "success": true, "data": { "steps": [
     *   { "id": 1, "title": "...", "subtitle": "...", "requires_input": false }
     * ] } }
     * ```
     */
    @GET("tenants/me/morning-checklist")
    suspend fun getChecklistConfig(): ApiResponse<MorningChecklistConfigDto>

    /**
     * Report a completed morning checklist session to the server.
     *
     * Endpoint: `POST /morning-checklist/complete`
     *
     * 404 → silently tolerated; local prefs are updated regardless.
     *
     * @param body Completion payload including date key, staff id, and checked steps.
     */
    @POST("morning-checklist/complete")
    suspend fun postCompletion(
        @Body body: MorningChecklistCompleteBody,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>
}
